
#include "../CoreGraphics/CGGeometry.h"

@import <Foundation/CPObject.j>


_CPMenuManagerScrollingStateUp      = -1,
_CPMenuManagerScrollingStateDown    = 1,
_CPMenuManagerScrollingStateNone    = 0;

var STICKY_TIME_INTERVAL        = 500;

var SharedMenuManager = nil;

@implementation _CPMenuManager: CPObject
{
    CPTimeInterval      _startTime;
    int                 _scrollingState;
    CGPoint             _lastGlobalLocation;

    CPView              _lastMouseOverMenuView;

    CGRect              _constraintRect;
    CPMutableArray      _menuContainerStack;

    Function            _trackingCallback;
}

+ (_CPMenuManager)sharedMenuManager
{
    if (!SharedMenuManager)
        SharedMenuManager = [[_CPMenuManager alloc] init];

    return SharedMenuManager;
}

- (id)init
{
    if (SharedMenuManager)
        return SharedMenuManager;

    return [super init];    
}

- (id)trackingMenuContainer
{
    return _menuContainerStack[0];
}

- (CPMenu)trackingMenu
{
    return [[self trackingMenuContainer] menu];
}

- (void)beginTracking:(CPEvent)anEvent
        menuContainer:(id)aMenuContainer
       constraintRect:(CGRect)aRect
             callback:(Function)aCallback
{
    CPApp._activeMenu = [aMenuContainer menu];

    _startTime = [anEvent timestamp];//new Date();
    _scrollingState = _CPMenuManagerScrollingStateNone;

    _constraintRect = aRect;
    _trackingCallback = aCallback;
    _menuContainerStack = [aMenuContainer];

    [self trackEvent:anEvent];
}

- (void)trackEvent:(CPEvent)anEvent
{
    var type = [anEvent type],
        trackingMenu = [self trackingMenu];

    // Close Menu Event.
    if (type === CPAppKitDefined)
    {
        // Stop all periodic events at this point.
        [CPEvent stopPeriodicEvents];

        // Get the original menu.
        var menu = [self trackingMenu],
            highlightedItem = [menu highlightedItem];

        // Hide all submenus.
        [self showMenu:nil fromMenu:menu atPoint:nil];

        var delegate = [menu delegate];

        if ([delegate respondsToSelector:@selector(menuDidClose:)])
            [delegate menuDidClose:menu];

        if (_trackingCallback)
            _trackingCallback([self trackingMenuContainer], menu);

        [[CPNotificationCenter defaultCenter]
            postNotificationName:CPMenuDidEndTrackingNotification
                          object:menu];

        CPApp._activeMenu = nil;

        return;
    }

    [CPApp setTarget:self selector:@selector(trackEvent:) forNextEventMatchingMask:CPPeriodicMask | CPMouseMovedMask | CPLeftMouseDraggedMask | CPLeftMouseUpMask | CPAppKitDefinedMask untilDate:nil inMode:nil dequeue:YES];

    // Periodic events don't have a valid location.
    var globalLocation = type === CPPeriodic ? _lastGlobalLocation : [anEvent globalLocation];

    // Remember this for the next periodic event.
    _lastGlobalLocation = globalLocation;

    // Find which menu window the mouse is currently on top of
    var activeMenuContainer = [self menuContainerForPoint:globalLocation],
        menuLocation = [activeMenuContainer convertGlobalToBase:globalLocation],
        activeItemIndex = activeMenuContainer ? [activeMenuContainer itemIndexAtPoint:menuLocation] : CPNotFound,
        activeMenu = activeMenuContainer ? [activeMenuContainer menu] : nil,
        activeItem = activeMenuContainer ? [activeMenu itemAtIndex:activeItemIndex] : nil,
        mouseOverMenuView = activeMenuContainer ? [activeItem view] : nil;

    if (type === CPPeriodic)
    {
        if (_scrollingState === _CPMenuManagerScrollingStateUp)
            [activeMenuContainer scrollUp];

        else if (_scrollingState === _CPMenuManagerScrollingStateDown)
            [activeMenuContainer scrollDown];
    }

    // If we're over a custom menu view...
    if (mouseOverMenuView)
    {
        if (!_lastMouseOverMenuView)
            [menu _highlightItemAtIndex:CPNotFound];
        
        if (_lastMouseOverMenuView != mouseOverMenuView)
        {
            [mouseOverMenuView mouseExited:anEvent];
            // FIXME: Possibly multiple of these?
            [_lastMouseOverMenuView mouseEntered:anEvent];
            
            _lastMouseOverMenuView = mouseOverMenuView;
        }
        
        [self sendEvent:[CPEvent mouseEventWithType:type location:menuLocation modifierFlags:[anEvent modifierFlags] 
            timestamp:[anEvent timestamp] windowNumber:[self windowNumber] context:nil 
            eventNumber:0 clickCount:[anEvent clickCount] pressure:[anEvent pressure]]];
    }
    else
    {
        if (_lastMouseOverMenuView)
        {
            [_lastMouseOverMenuView mouseExited:anEvent];
            _lastMouseOverMenuView = nil;
        }
        
        [activeMenu _highlightItemAtIndex:activeItemIndex];
        
        if (type === CPMouseMoved || type === CPLeftMouseDragged || type === CPLeftMouseDown)
        {
            var oldScrollingState = _scrollingState;

            _scrollingState = [activeMenuContainer scrollingStateForPoint:globalLocation];

            if (_scrollingState !== oldScrollingState)
            {
                if (_scrollingState === _CPMenuManagerScrollingStateNone)
                    [CPEvent stopPeriodicEvents];
            
                else if (oldScrollingState === _CPMenuManagerScrollingStateNone)
                    [CPEvent startPeriodicEventsAfterDelay:0.0 withPeriod:0.04];
            }
        }
        else if (type === CPLeftMouseUp && ([anEvent timestamp] - _startTime > STICKY_TIME_INTERVAL))
            [[self trackingMenu] cancelTracking];
    }

    // If the item has a submenu, show it.
    if ([activeItem hasSubmenu])// && [activeItem action] === @selector(submenuAction:))
    {
        var activeItemRect = [activeMenuContainer rectForItemAtIndex:activeItemIndex];

        if ([activeMenuContainer isMenuBar])
            var newMenuOrigin = CGPointMake(CGRectGetMinX(activeItemRect), CGRectGetMaxY(activeItemRect));
        else
            var newMenuOrigin = CGPointMake(CGRectGetMaxX(activeItemRect), CGRectGetMinY(activeItemRect));

        newMenuOrigin = [activeMenuContainer convertBaseToGlobal:newMenuOrigin];

        [self showMenu:[activeItem submenu] fromMenu:[activeItem menu] atPoint:newMenuOrigin];
    }

    // This handles both the case where we've moved away from the menu, and where 
    // we've moved to an item without a submenu.
    else
        [self showMenu:nil fromMenu:activeMenu atPoint:CGPointMakeZero()];
}


- (id)menuContainerForPoint:(float)aGlobalLocation
{
    var count = [_menuContainerStack count],
        firstMenuContainer = _menuContainerStack[0];

    // Trivial case.
    if (count === 1)
        return firstMenuContainer;

    var firstMenuWindowIndex = 0,
        lastMenuWindowIndex = count - 1;

    // If the first menu container is a bar, then it has to fall strictly within its bounds.
    if ([firstMenuContainer isMenuBar])
    {
        if (CGRectContainsPoint([firstMenuContainer globalFrame], aGlobalLocation))
            return firstMenuContainer;

        firstMenuWindowIndex = 1;
    }

    var index = count,
        x = aGlobalLocation.x,
        closerDeltaX = Infinity,
        closerMenuContainer = nil;

    while (index-- > firstMenuWindowIndex)
    {
        var menuContainer = _menuContainerStack[index],
            menuContainerFrame = [menuContainer globalFrame],
            menuContainerMinX = _CGRectGetMinX(menuContainerFrame),
            menuContainerMaxX = _CGRectGetMaxX(menuContainerFrame);

        // If within the x bounds of this menu container, return it.
        if (x < menuContainerMaxX && x >= menuContainerMinX)
            return menuContainer;

        // If this is either the first or last menu *window*, check to see how close we are to it.
        if (index === firstMenuWindowIndex || index === lastMenuWindowIndex)
        {
            var deltaX = ABS(x < menuContainerMinX ? menuContainerMinX - x : menuContainerMaxX - x);

            if (deltaX < closerDeltaX)
            {
                closerMenuContainer = menuContainer;
                closerDeltaX = deltaX;
            }
        }
    }

    return closerMenuContainer;
}

- (void)showMenu:(CPMenu)newMenu fromMenu:(CPMenu)baseMenu atPoint:(CGPoint)aGlobalLocation
{//console.log("SM: " + [self trackingMenu] + " SHOW MENU: " + newMenu + " from menu " + baseMenu);
    var count = _menuContainerStack.length,
        index = count;

    // Hide all menus up to the base menu...
    while (index--)
    {
        var menuContainer = _menuContainerStack[index];

        if ([menuContainer menu] === baseMenu)
            break;

        [[menuContainer menu] _highlightItemAtIndex:CPNotFound];

        [menuContainer orderOut:self];
        [menuContainer setMenu:nil];

        [_CPMenuWindow poolMenuWindow:menuContainer];
        [_menuContainerStack removeObjectAtIndex:index];
    }

    if (!newMenu)
        return;

    // Unhighlight any previously highlighted item.
    [newMenu _highlightItemAtIndex:CPNotFound];

    var menuWindow = [_CPMenuWindow menuWindowWithMenu:newMenu font:[_menuContainerStack[0] font]];

    [_menuContainerStack addObject:menuWindow];

    [menuWindow setConstraintRect:_constraintRect];

    // If our parent menu is a menu bar...
    if (baseMenu === [self trackingMenu] && [[self trackingMenuContainer] isMenuBar])
        [menuWindow setBackgroundStyle:_CPMenuWindowMenuBarBackgroundStyle];
    else
        [menuWindow setBackgroundStyle:_CPMenuWindowPopUpBackgroundStyle];        
    
    [menuWindow setFrameOrigin:aGlobalLocation];
    [menuWindow orderFront:self];
}

@end
