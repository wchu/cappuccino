/*
 * CPOutlineView.j
 * AppKit
 *
 * Created by Francisco Tolmasky.
 * Copyright 2009, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import "CPTableColumn.j"
@import "CPTableView.j"

#include "CoreGraphics/CGGeometry.h"


CPOutlineViewColumnDidMoveNotification          = @"CPOutlineViewColumnDidMoveNotification";
CPOutlineViewColumnDidResizeNotification        = @"CPOutlineViewColumnDidResizeNotification";
CPOutlineViewItemDidCollapseNotification        = @"CPOutlineViewItemDidCollapseNotification";
CPOutlineViewItemDidExpandNotification          = @"CPOutlineViewItemDidExpandNotification";
CPOutlineViewItemWillCollapseNotification       = @"CPOutlineViewItemWillCollapseNotification";
CPOutlineViewItemWillExpandNotification         = @"CPOutlineViewItemWillExpandNotification";
CPOutlineViewSelectionDidChangeNotification     = @"CPOutlineViewSelectionDidChangeNotification";
CPOutlineViewSelectionIsChangingNotification    = @"CPOutlineViewSelectionIsChangingNotification";

var CPOutlineViewDataSource_outlineView_setObjectValue_forTableColumn_byItem_                       = 1 << 1,
    CPOutlineViewDataSource_outlineView_shouldDeferDisplayingChildrenOfItem_                        = 1 << 2,

    CPOutlineViewDataSource_outlineView_acceptDrop_item_childIndex_                                 = 1 << 3,
    CPOutlineViewDataSource_outlineView_validateDrop_proposedItem_proposedChildIndex_               = 1 << 4,
    CPOutlineViewDataSource_outlineView_validateDrop_proposedRow_proposedDropOperation_             = 1 << 5,
    CPOutlineViewDataSource_outlineView_namesOfPromisedFilesDroppedAtDestination_forDraggedItems_   = 1 << 6,

    CPOutlineViewDataSource_outlineView_itemForPersistentObject_                                    = 1 << 7,
    CPOutlineViewDataSource_outlineView_persistentObjectForItem_                                    = 1 << 8,

    CPOutlineViewDataSource_outlineView_writeItems_toPasteboard_                                    = 1 << 9,

    CPOutlineViewDataSource_outlineView_sortDescriptorsDidChange_                                   = 1 << 10;

@implementation CPOutlineView : CPTableView
{
    id              _outlineViewDataSource;
    id              _outlineViewDelegate;
    CPTableColumn   _outlineTableColumn;

    float           _indentationPerLevel;
    BOOL            _indentationMarkerFollowsDataView;

    CPInteger       _implementedOutlineViewDataSourceMethods;

    Object          _rootItemInfo;
    CPMutableArray  _itemsForRows;
    Object          _itemInfosForItems;

    CPControl       _disclosureControlPrototype;
    CPArray         _disclosureControlsForRows;
    CPData          _disclosureControlData;
    CPArray         _disclosureControlQueue;
}

- (id)initWithFrame:(CGRect)aFrame
{
    self = [super initWithFrame:aFrame];

    if (self)
    {
        // The root item has weight "0", thus represents the weight solely of its descendants.
        _rootItemInfo = { isExpanded:YES, isExpandable:NO, level:-1, row:-1, children:[], weight:0 };

        _itemsForRows = [];
        _itemInfosForItems = { };
        _disclosureControlsForRows = [];

        [self setIndentationPerLevel:16.0];
        [self setIndentationMarkerFollowsDataView:YES];

        [super setDataSource:[[_CPOutlineViewTableViewDataSource alloc] initWithOutlineView:self]];

        [self setDisclosureControlPrototype:[[CPDisclosureButton alloc] initWithFrame:CGRectMake(0.0, 0.0, 10.0, 10.0)]];
    }

    return self;
}

- (void)setDataSource:(id)aDataSource
{
    if (_outlineViewDataSource === aDataSource)
        return;

    if (![aDataSource respondsToSelector:@selector(outlineView:child:ofItem:)])
        [CPException raise:CPInternalInconsistencyException reason:"Data source must implement 'outlineView:child:ofItem:'"];

    if (![aDataSource respondsToSelector:@selector(outlineView:isItemExpandable:)])
        [CPException raise:CPInternalInconsistencyException reason:"Data source must implement 'outlineView:isItemExpandable:'"];

    if (![aDataSource respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)])
        [CPException raise:CPInternalInconsistencyException reason:"Data source must implement 'outlineView:numberOfChildrenOfItem:'"];

    if (![aDataSource respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)])
        [CPException raise:CPInternalInconsistencyException reason:"Data source must implement 'outlineView:objectValueForTableColumn:byItem:'"];

    _outlineViewDataSource = aDataSource;
    _implementedOutlineViewDataSourceMethods = 0;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:setObjectValue:forTableColumn:byItem:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_setObjectValue_forTableColumn_byItem_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:shouldDeferDisplayingChildrenOfItem:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_shouldDeferDisplayingChildrenOfItem_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:acceptDrop:item:childIndex:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_acceptDrop_item_childIndex_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:validateDrop:proposedItem:proposedChildIndex:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_validateDrop_proposedItem_proposedChildIndex_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:validateDrop:proposedRow:proposedDropOperation:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_validateDrop_proposedRow_proposedDropOperation_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:namesOfPromisedFilesDroppedAtDestination:forDraggedItems:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_namesOfPromisedFilesDroppedAtDestination_forDraggedItems_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:itemForPersistentObject:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_itemForPersistentObject_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:persistentObjectForItem:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_persistentObjectForItem_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:writeItems:toPasteboard:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_writeItems_toPasteboard_;

    if ([_outlineViewDataSource respondsToSelector:@selector(outlineView:sortDescriptorsDidChange:)])
        _implementedOutlineViewDataSourceMethods |= CPOutlineViewDataSource_outlineView_sortDescriptorsDidChange_;

    [self reloadData];
}

- (id)dataSource
{
    return _outlineViewDataSource;
}

- (BOOL)isExpandable:(id)anItem
{
    if (!anItem)
        return YES;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return NO;

    return itemInfo.isExpandable;
}

- (void)isItemExpanded:(id)anItem
{
    if (!anItem)
        return YES;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return NO;

    return itemInfo.isExpanded;
}

- (void)expandItem:(id)anItem
{
    if (!anItem)
        return;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return;

    if (itemInfo.isExpanded)
        return;

    itemInfo.isExpanded = YES;

    [self reloadItem:anItem reloadChildren:YES];
}

- (void)collapseItem:(id)anItem
{
    if (!anItem)
        return;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return;

    if (!itemInfo.isExpanded)
        return;

    itemInfo.isExpanded = NO;

    [self reloadItem:anItem reloadChildren:YES];
}

- (void)reloadItem:(id)anItem
{
    [self reloadItem:anItem reloadChildren:NO];
}

- (void)reloadItem:(id)anItem reloadChildren:(BOOL)shouldReloadChildren
{
    if (!!shouldReloadChildren || !anItem)
        _loadItemInfoForItem(self, anItem);
    else
        _reloadItem(self, anItem);

    [super reloadData];
}

- (id)itemAtRow:(CPInteger)aRow
{
    return _itemsForRows[aRow] || nil;
}

- (CPInteger)rowForItem:(id)aItem
{
    if (!anItem)
        return _rootItemInfo.row;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return CPNotFound;

    return itemInfo.row;
}

- (void)setOutlineTableColumn:(CPTableColumn)aTableColumn
{
    if (_outlineTableColumn === aTableColumn)
        return;

    _outlineTableColumn = aTableColumn;

    // FIXME: efficiency.
    [self reloadData];
}

- (CPTableColumn)outlineTableColumn
{
    return _outlineTableColumn;
}

- (CPInteger)levelForItem:(id)anItem
{
    if (!anItem)
        return _rootItemInfo.level;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return CPNotFound;

    return itemInfo.level;
}

- (CPInteger)levelForRow:(CPInteger)aRow
{
    return [self levelForItem:[self itemAtRow:aRow]];
}

- (void)setIndentationPerLevel:(float)anIndentationWidth
{
    if (_indentationPerLevel === anIndentationWidth)
        return;

    _indentationPerLevel = anIndentationWidth;

    // FIXME: efficiency!!!!
    [self reloadData];
}

- (float)indentationPerLevel
{
    return _indentationPerLevel;
}

- (void)setIndentationMarkerFollowsDataView:(BOOL)indentationMarkerShouldFollowDataView
{
    if (_indentationMarkerFollowsDataView === indentationMarkerShouldFollowDataView)
        return;

    _indentationMarkerFollowsDataView = indentationMarkerShouldFollowDataView;

    // !!!!
    [self reloadData];
}

- (BOOL)indentationMarkerFollowsDataView
{
    return _indentationMarkerFollowsDataView;
}

- (id)parentForItem:(id)anItem
{
    if (!anItem)
        return nil;

    var itemInfo = _itemInfosForItems[[anItem UID]];

    if (!itemInfo)
        return nil;

    return itemInfo.parent;
}

- (CGRect)frameOfOutlineDataViewAtColumn:(CPInteger)aColumn row:(CPInteger)aRow
{
    var frame = [super frameOfDataViewAtColumn:aColumn row:aRow],
        indentationWidth = ([self levelForRow:aRow] + 1) * [self indentationPerLevel];

    frame.origin.x += indentationWidth;
    frame.size.width -= indentationWidth;

    return frame;
}

- (void)setDelegate:(id)aDelegate
{
    if (_outlineViewDelegate === aDelegate)
        return;

    var defaultCenter = [CPNotificationCenter defaultCenter];

    if (_outlineViewDelegate)
    {
        if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewColumnDidMove:)])
            [defaultCenter
                removeObserver:_outlineViewDelegate
                          name:CPOutlineViewColumnDidMoveNotification
                        object:self];

        if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewColumnDidResize:)])
            [defaultCenter
                removeObserver:_outlineViewDelegate
                          name:CPOutlineViewColumnDidResizeNotification
                        object:self];

        if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewSelectionDidChange:)])
            [defaultCenter
                removeObserver:_outlineViewDelegate
                          name:CPOutlineViewSelectionDidChangeNotification
                        object:self];

        if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewSelectionIsChanging:)])
            [defaultCenter
                removeObserver:_outlineViewDelegate
                          name:CPOutlineViewSelectionIsChangingNotification
                        object:self];
    }

    _outlineViewDelegate = aDelegate;/*
    _implementedDelegateMethods = 0;

    if ([_outlineViewDelegate respondsToSelector:@selector(selectionShouldChangeInTableView:)])
        _implementedDelegateMethods |= CPTableViewDelegate_selectionShouldChangeInTableView_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:dataViewForTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_dataViewForTableColumn_row_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:didClickTableColumn:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_didClickTableColumn_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:didDragTableColumn:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_didDragTableColumn_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:heightOfRow:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_heightOfRow_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:isGroupRow:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_isGroupRow_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:mouseDownInHeaderOfTableColumn:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_mouseDownInHeaderOfTableColumn_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:nextTypeSelectMatchFromRow:toRow:forString:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_nextTypeSelectMatchFromRow_toRow_forString_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:selectionIndexesForProposedSelection:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_selectionIndexesForProposedSelection_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldEditTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldEditTableColumn_row_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldSelectRow:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldSelectRow_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldSelectTableColumn:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldSelectTableColumn_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldShowViewExpansionForTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldShowViewExpansionForTableColumn_row_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldTrackView:forTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldTrackView_forTableColumn_row_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:shouldTypeSelectForEvent:withCurrentSearchString:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_shouldTypeSelectForEvent_withCurrentSearchString_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:toolTipForView:rect:tableColumn:row:mouseLocation:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_toolTipForView_rect_tableColumn_row_mouseLocation_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:typeSelectStringForTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_typeSelectStringForTableColumn_row_;

    if ([_outlineViewDelegate respondsToSelector:@selector(tableView:willDisplayView:forTableColumn:row:)])
        _implementedDelegateMethods |= CPTableViewDelegate_tableView_willDisplayView_forTableColumn_row_;
*/
    if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewColumnDidMove:)])
        [defaultCenter
            addObserver:_outlineViewDelegate
            selector:@selector(outlineViewColumnDidMove:)
            name:CPOutlineViewColumnDidMoveNotification
            object:self];

    if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewColumnDidResize:)])
        [defaultCenter
            addObserver:_outlineViewDelegate
            selector:@selector(outlineViewColumnDidMove:)
            name:CPOutlineViewColumnDidResizeNotification
            object:self];

    if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewSelectionDidChange:)])
        [defaultCenter
            addObserver:_outlineViewDelegate
            selector:@selector(outlineViewSelectionDidChange:)
            name:CPOutlineViewSelectionDidChangeNotification
            object:self];

    if ([_outlineViewDelegate respondsToSelector:@selector(outlineViewSelectionIsChanging:)])
        [defaultCenter
            addObserver:_outlineViewDelegate
            selector:@selector(outlineViewSelectionIsChanging:)
            name:CPOutlineViewSelectionIsChangingNotification
            object:self];
}

- (id)delegate
{
    return _outlineViewDelegate;
}

- (void)setDisclosureControlPrototype:(CPControl)aControl
{
    _disclosureControlPrototype = aControl;
    _disclosureControlData = nil;
    _disclosureControlQueue = [];

    // fIXME: reall?
    [self reloadData];
}

- (void)reloadData
{
    [self reloadItem:nil reloadChildren:YES];
}

- (CGRect)frameOfDataViewAtColumn:(CPInteger)aColumn row:(CPInteger)aRow
{
    var tableColumn = [self tableColumns][aColumn];

    if (tableColumn === _outlineTableColumn)
        return [self frameOfOutlineDataViewAtColumn:aColumn row:aRow];

    return [super frameOfDataViewAtColumn:aColumn row:aRow];
}

- (void)_loadDataViewsInRows:(CPIndexSet)rows columns:(CPIndexSet)columns
{
    [super _loadDataViewsInRows:rows columns:columns];

    var outlineColumn = [[self tableColumns] indexOfObjectIdenticalTo:[self outlineTableColumn]];

    if (![columns containsIndex:outlineColumn])
        return;

    var rowArray = [];

    [rows getIndexes:rowArray maxCount:-1 inIndexRange:nil];

    var rowIndex = 0,
        rowsCount = rowArray.length;

    for (; rowIndex < rowsCount; ++rowIndex)
    {
        var row = rowArray[rowIndex],
            item = _itemsForRows[row],
            isExpandable = [self isExpandable:item];

       if (!isExpandable)
            continue;

        var control = [self _dequeueDisclosureControl],
            frame = [control frame],
            dataViewFrame = [self frameOfDataViewAtColumn:outlineColumn row:row];

        frame.origin.x = _indentationMarkerFollowsDataView ? _CGRectGetMinX(dataViewFrame) - _CGRectGetWidth(frame) : 0.0;
        frame.origin.y = _CGRectGetMinY(dataViewFrame);
        frame.size.height = _CGRectGetHeight(dataViewFrame);
        // FIXME: center instead?
        //frame.origin.y = _CGRectGetMidY(dataViewFrame) - _CGRectGetHeight(frame) / 2.0;

        _disclosureControlsForRows[row] = control;

        [control setState:[self isItemExpanded:item] ? CPOnState : CPOffState];
        [control setFrame:frame];

        [self addSubview:control];
    }
}

- (void)_unloadDataViewsInRows:(CPIndexSet)rows columns:(CPIndexSet)columns
{
    [super _unloadDataViewsInRows:rows columns:columns];

    var outlineColumn = [[self tableColumns] indexOfObjectIdenticalTo:[self outlineTableColumn]];

    if (![columns containsIndex:outlineColumn])
        return;

    var rowArray = [];

    [rows getIndexes:rowArray maxCount:-1 inIndexRange:nil];

    var rowIndex = 0,
        rowsCount = rowArray.length;

    for (; rowIndex < rowsCount; ++rowIndex)
    {
        var row = rowArray[rowIndex],
            control = _disclosureControlsForRows[row];

        if (!control)
            continue;

        [control removeFromSuperview];

        [self _enqueueDisclosureControl:control];

        _disclosureControlsForRows[row] = nil;
    }
}

- (void)_toggleFromDisclosureControl:(CPControl)aControl
{
    var controlFrame = [aControl frame],
        item = [self itemAtRow:[self rowAtPoint:_CGPointMake(_CGRectGetMinX(controlFrame), _CGRectGetMidY(controlFrame))]];

    if ([self isItemExpanded:item])
        [self collapseItem:item];

    else
        [self expandItem:item];
}

- (void)_enqueueDisclosureControl:(CPControl)aControl
{
    _disclosureControlQueue.push(aControl);
}

- (CPControl)_dequeueDisclosureControl
{
    if (_disclosureControlQueue.length)
        return _disclosureControlQueue.pop();

    if (!_disclosureControlData)
        if (!_disclosureControlPrototype)
            return nil;
        else
            _disclosureControlData = [CPKeyedArchiver archivedDataWithRootObject:_disclosureControlPrototype];

    var disclosureControl = [CPKeyedUnarchiver unarchiveObjectWithData:_disclosureControlData];

    [disclosureControl setTarget:self];
    [disclosureControl setAction:@selector(_toggleFromDisclosureControl:)];

    return disclosureControl;
}

- (void)_noteSelectionIsChanging
{
    [[CPNotificationCenter defaultCenter]
        postNotificationName:CPOutlineViewSelectionIsChangingNotification
                      object:self
                    userInfo:nil];
}

- (void)_noteSelectionDidChange
{
    [[CPNotificationCenter defaultCenter]
        postNotificationName:CPOutlineViewSelectionDidChangeNotification
                      object:self
                    userInfo:nil];
}

@end

var _reloadItem = function(/*CPOutlineView*/ anOutlineView, /*id*/ anItem)
{
    if (!anItem)
        return;

    // Get the existing info if it exists.
    var itemInfosForItems = anOutlineView._itemInfosForItems,
        dataSource = anOutlineView._outlineViewDataSource,
        itemUID = [anItem UID],
        itemInfo = itemInfosForItems[itemUID];

    // If we're not in the tree, then just bail.
    if (!itemInfo)
        return [];

    // See if the item itself can be swapped out.
    var parent = itemInfo.parent,
        parentItemInfo = parent ? itemInfosForItems[[parent UID]] : anOutlineView._rootItemInfo,
        parentChildren = parentItemInfo.children,
        index = [parentChildren indexOfObjectIdenticalTo:anItem],
        newItem = [dataSource outlineView:anOutlineView child:index ofItem:parent];

    if (anItem !== newItem)
    {
        itemInfosForItems[[anItem UID]] = nil;
        itemInfosForItems[[newItem UID]] = itemInfo;

        parentChildren[index] = newItem;
        anOutlineView._itemsForRows[itemInfo.row] = newItem;
    }

    itemInfo.isExpandable = [dataSource outlineView:anOutlineView isItemExpandable:newItem];
    itemInfo.isExpanded = itemInfo.isExpandable && itemInfo.isExpanded;
}

var _loadItemInfoForItem = function(/*CPOutlineView*/ anOutlineView, /*id*/ anItem,  /*BOOL*/ isIntermediate)
{
    var itemInfosForItems = anOutlineView._itemInfosForItems,
        dataSource = anOutlineView._outlineViewDataSource;

    if (!anItem)
        var itemInfo = anOutlineView._rootItemInfo;

    else
    {
        // Get the existing info if it exists.
        var itemUID = [anItem UID],
            itemInfo = itemInfosForItems[itemUID];

        // If we're not in the tree, then just bail.
        if (!itemInfo)
            return [];

        itemInfo.isExpandable = [dataSource outlineView:anOutlineView isItemExpandable:anItem];

        // If we were previously expanded, but now no longer expandable, "de-expand".
        // NOTE: we are *not* collapsing, thus no notification is posted.
        if (!itemInfo.isExpandable && itemInfo.isExpanded)
        {
            itemInfo.isExpanded = NO;
            itemInfo.children = [];
        }
    }

    // The root item does not count as a descendant.
    var weight = itemInfo.weight,
        descendants = anItem ? [anItem] : [];

    if (itemInfo.isExpanded && (!(anOutlineView._implementedOutlineViewDataSourceMethods & CPOutlineViewDataSource_outlineView_shouldDeferDisplayingChildrenOfItem_) ||
        ![dataSource outlineView:anOutlineView shouldDeferDisplayingChildrenOfItem:anItem]))
    {
        var index = 0,
            count = [dataSource outlineView:anOutlineView numberOfChildrenOfItem:anItem],
            level = itemInfo.level + 1;

        itemInfo.children = [];

        for (; index < count; ++index)
        {
            var childItem = [dataSource outlineView:anOutlineView child:index ofItem:anItem],
                childItemInfo = itemInfosForItems[[childItem UID]];

            if (!childItemInfo)
            {
                childItemInfo = { isExpanded:NO, isExpandable:NO, children:[], weight:1 };
                itemInfosForItems[[childItem UID]] = childItemInfo;
            }

            itemInfo.children[index] = childItem;

            var childDescendants = _loadItemInfoForItem(anOutlineView, childItem, YES);

            childItemInfo.parent = anItem;
            childItemInfo.level = level;
            descendants = descendants.concat(childDescendants);
        }
    }

    itemInfo.weight = descendants.length;

    if (!isIntermediate)
    {
        // row = -1 is the root item, so just go to row 0 since it is ignored.
        var index = MAX(itemInfo.row, 0),
            itemsForRows = anOutlineView._itemsForRows;

        descendants.unshift(index, weight);

        itemsForRows.splice.apply(itemsForRows, descendants);

        var count = itemsForRows.length;

        for (; index < count; ++index)
            itemInfosForItems[[itemsForRows[index] UID]].row = index;

        var deltaWeight = itemInfo.weight - weight;

        if (deltaWeight !== 0)
        {
            var parent = itemInfo.parent;

            while (parent)
            {
                var parentItemInfo = itemInfosForItems[[parent UID]];

                parentItemInfo.weight += deltaWeight;
                parent = parentItemInfo.parent;
            }

            if (anItem)
                anOutlineView._rootItemInfo.weight += deltaWeight;
        }
    }

    return descendants;
}

@implementation _CPOutlineViewTableViewDataSource : CPObject
{
    CPObject _outlineView;
}

- (id)initWithOutlineView:(CPOutlineView)anOutlineView
{
    self = [super init];

    if (self)
        _outlineView = anOutlineView;

    return self;
}

- (CPInteger)numberOfRowsInTableView:(CPTableView)anOutlineView
{
    return _outlineView._itemsForRows.length;
}

- (id)tableView:(CPTableView)aTableView objectValueForTableColumn:(CPTableColumn)aTableColumn row:(CPInteger)aRow
{
    return [_outlineView._outlineViewDataSource outlineView:_outlineView objectValueForTableColumn:aTableColumn byItem:_outlineView._itemsForRows[aRow]];
}

@end

@implementation _CPOutlineViewTableViewDelegate : CPObject
{
    CPOutlineView   _outlineView;
}

- (id)initWithOutlineView:(CPOutlineView)anOutlineView
{
    self = [super init];

    if (self)
        _outlineView = anOutlineView;

    return self;
}

@end

@implementation CPDisclosureButton : CPButton
{
    float _angle;
}

- (id)initWithFrame:(CGRect)aFrame
{
    self = [super initWithFrame:aFrame];

    if (self)
        [self setBordered:NO];

    return self;
}

- (void)setState:(CPState)aState
{
    [super setState:aState];

    if ([self state] === CPOnState)
        _angle = 0.0;

    else
        _angle = -PI_2;
}

- (void)drawRect:(CGRect)aRect
{
    var bounds = [self bounds],
        context = [[CPGraphicsContext currentContext] graphicsPort];

    CGContextBeginPath(context);

    CGContextTranslateCTM(context, _CGRectGetWidth(bounds) / 2.0, _CGRectGetHeight(bounds) / 2.0);
    CGContextRotateCTM(context, _angle);
    CGContextTranslateCTM(context, -_CGRectGetWidth(bounds) / 2.0, -_CGRectGetHeight(bounds) / 2.0);

    // Center, but crisp.
    CGContextTranslateCTM(context, FLOOR((_CGRectGetWidth(bounds) - 9.0) / 2.0), FLOOR((_CGRectGetHeight(bounds) - 8.0) / 2.0));

    CGContextMoveToPoint(context, 0.0, 0.0);
    CGContextAddLineToPoint(context, 9.0, 0.0);
    CGContextAddLineToPoint(context, 4.5, 8.0);
    CGContextAddLineToPoint(context, 0.0, 0.0);

    CGContextClosePath(context);

    CGContextSetFillColor(context, ([self themeState] & CPThemeState("highlighted")) ? [CPColor blackColor] : [CPColor grayColor]);
    CGContextFillPath(context);
}

@end
