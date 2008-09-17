/*
 * CPWebView.j
 * AppKit
 *
 * Created by Thomas Robinson.
 * Copyright 2008, 280 North, Inc.
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

import "CPView.j"

// FIXME: implement these where possible:
/*
CPWebViewDidBeginEditingNotification            = "CPWebViewDidBeginEditingNotification";
CPWebViewDidChangeNotification                  = "CPWebViewDidChangeNotification";
CPWebViewDidChangeSelectionNotification         = "CPWebViewDidChangeSelectionNotification";
CPWebViewDidChangeTypingStyleNotification       = "CPWebViewDidChangeTypingStyleNotification";
CPWebViewDidEndEditingNotification              = "CPWebViewDidEndEditingNotification";
CPWebViewProgressEstimateChangedNotification    = "CPWebViewProgressEstimateChangedNotification";
*/
CPWebViewProgressStartedNotification            = "CPWebViewProgressStartedNotification";
CPWebViewProgressFinishedNotification           = "CPWebViewProgressFinishedNotification";

// FIXME: somehow make CPWebView work with CPScrollView instead of native scrollbars (is this even possible?)

@implementation CPWebView : CPView
{
    IFrame      _iframe;
    CPString    _mainFrameURL;
    CPArray     _backwardStack;
    CPArray     _forwardStack;
    
    BOOL        _ignoreLoadEvent;
    
    id          _downloadDelegate;
    id          _frameLoadDelegate;
    id          _policyDelegate;
    id          _resourceLoadDelegate;
    id          _UIDelegate;
    
    CPWebScriptObject _wso;
}

- (id)initWithFrame:(CPRect)frameRect frameName:(CPString)frameName groupName:(CPString)groupName
{
    if (self = [self initWithFrame:frameRect])
    {
        _iframe.name = frameName;
    }
    return self
}

- (id)initWithFrame:(CPRect)aFrame
{
    if (self = [super initWithFrame:aFrame])
    {
        _mainFrameURL = nil;
        _backwardStack = [];
        _forwardStack = [];
        _ignoreLoadEvent = NO;
        
        _iframe = document.createElement("iframe");
        _iframe.name = "iframe_" + Math.floor(Math.random()*10000);
        _iframe.style.width = "100%";
        _iframe.style.height = "100%";
        _iframe.style.borderWidth = "0px";
        
        var loadCallback = function() {
		    // HACK: this block handles the case where we don't know about loads initiated by the user clicking a link
		    if (!_ignoreLoadEvent)
		    {
		        // post the start load notification
		        [self _startedLoading];
		        
		        if (_mainFrameURL)
		            [_backwardStack addObject:_mainFrameURL];
		            
		        // FIXME: this doesn't actually get the right URL for different domains. Probably not be possible due to browser security restrictions.
                _mainFrameURL = _iframe.src;
                
    	        [_forwardStack removeAllObjects];
		    }
		    _ignoreLoadEvent = NO;
		    
            [self _finishedLoading]
		}
		
		if (_iframe.addEventListener)
		    _iframe.addEventListener("load", loadCallback, false);
		else if (_iframe.attachEvent)
    		_iframe.attachEvent("onload", loadCallback);
		    
        _DOMElement.appendChild(_iframe);
    }
    
    return self;
}

- (BOOL)drawsBackground
{
    return _iframe.style.backgroundColor != "";
}

- (void)setDrawsBackground:(BOOL)drawsBackround
{
    _iframe.style.backgroundColor = drawsBackround ? "white" : "";
}

- (CPString)mainFrameURL
{
    return _mainFrameURL;
}

- (void)_loadMainFrameURL
{
    [self _startedLoading];
    
    _ignoreLoadEvent = YES;
    _iframe.src = _mainFrameURL;
}

- (void)_startedLoading
{
    [[CPNotificationCenter defaultCenter] postNotificationName:CPWebViewProgressStartedNotification object:self];

    if ([_frameLoadDelegate respondsToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
        [_frameLoadDelegate webView:self didStartProvisionalLoadForFrame:nil]; // FIXME: give this a frame somehow?
}

- (void)_finishedLoading
{
    [[CPNotificationCenter defaultCenter] postNotificationName:CPWebViewProgressFinishedNotification object:self];

    if ([_frameLoadDelegate respondsToSelector:@selector(webView:didFinishLoadForFrame:)])
        [_frameLoadDelegate webView:self didFinishLoadForFrame:nil]; // FIXME: give this a frame somehow?
}

- (void)setMainFrameURL:(CPString)URLString
{    
    if (_mainFrameURL)
        [_backwardStack addObject:_mainFrameURL];
    _mainFrameURL = URLString;
    [_forwardStack removeAllObjects];
    
    [self _loadMainFrameURL];
}

- (IBAction)takeStringURLFrom:(id)sender
{
    [self setMainFrameURL:[sender stringValue]];
}

- (BOOL)goBack
{
    if (_backwardStack.length > 0)
    {
        if (_mainFrameURL)
            [_forwardStack addObject:_mainFrameURL];
        _mainFrameURL = [_backwardStack lastObject];
        [_backwardStack removeLastObject];
        
        [self _loadMainFrameURL];
        
        return YES;
    }
    return NO;
}

- (BOOL)goForward
{
    if (_forwardStack.length > 0)
    {
        if (_mainFrameURL)
            [_backwardStack addObject:_mainFrameURL];
        _mainFrameURL = [_forwardStack lastObject];
        [_forwardStack removeLastObject];
        
        [self _loadMainFrameURL];
        
        return YES;
    }
    return NO;
}

- (IBAction)goBack:(id)sender
{
    [self goBack];
}

- (IBAction)goForward:(id)sender
{
    [self goForward];
}

- (BOOL)canGoBack
{
    return (_backwardStack.length > 0);
}

- (BOOL)canGoForward
{
    return (_forwardStack.length > 0);
}

- (WebBackForwardList)backForwardList
{
    // FIXME: return a real WebBackForwardList?
    return { back: _backwardStack, forward: _forwardStack };
}

- (void)close
{
    _DOMElement.removeChild(_iframe);
}

- (Window)window
{
    return (_iframe.contentDocument && _iframe.contentDocument.defaultView) || _iframe.contentWindow;
}

- (CPWebScriptObject)windowScriptObject
{
    var win = [self window];
    if (!_wso || win != [_wso window])
    {
        if (win)
            _wso = [[CPWebScriptObject alloc] initWithWindow:win];
        else
            _wso = nil;
    }
    return _wso;
}

- (CPString)stringByEvaluatingJavaScriptFromString:(CPString)script
{
    var result = [self objectByEvaluatingJavaScriptFromString:script];
    return result ? String(result) : nil;
}

- (JSObject)objectByEvaluatingJavaScriptFromString:(CPString)script
{
    return [[self windowScriptObject] evaluateWebScript:script];
}

- (DOMCSSStyleDeclaration)computedStyleForElement:(DOMElement)element pseudoElement:(CPString)pseudoElement
{
    var win = [[self windowScriptObject] window];
    if (win)
    {
        // FIXME: IE version?
        return win.document.defaultView.getComputedStyle(element, pseudoElement);
    }
    return nil;
}

// Delegates:

// FIXME: implement more delegates, though most of these will likely never work with the iframe implementation

- (id)downloadDelegate
{
    return _downloadDelegate;
}
- (void)setDownloadDelegate:(id)anObject
{
    _downloadDelegate = anObject;
}
- (id)frameLoadDelegate
{
    return _frameLoadDelegate;
}
- (void)setFrameLoadDelegate:(id)anObject
{
    _frameLoadDelegate = anObject;
}
- (id)policyDelegate
{
    return _policyDelegate;
}
- (void)setPolicyDelegate:(id)anObject
{
    _policyDelegate = anObject;
}
- (id)resourceLoadDelegate
{
    return _resourceLoadDelegate;
}
- (void)setResourceLoadDelegate:(id)anObject
{
    _resourceLoadDelegate = anObject;
}
- (id)UIDelegate
{
    return _UIDelegate;
}
- (void)setUIDelegate:(id)anObject
{
    _UIDelegate = anObject;
}


- (void)loadHTMLString:(CPString)aString
{
    [self loadHTMLString:aString baseURL:nil];
}

- (void)loadHTMLString:(CPString)aString baseURL:(CPURL)URL
{
    // FIXME: do something with baseURL?
    
    // clear the iframe
    _iframe.src = "";

    // need to give the browser a chance to reset iframe, otherwise we'll be document.write()-ing the previous document 
    window.setTimeout(function() {
        var win = [self window];
        win.document.write(aString);
    }, 0);
}

@end


@implementation CPWebScriptObject : CPObject
{
    Window _window;
}

- (id)initWithWindow:(Window)aWindow
{
    if (self = [super init])
    {
        _window = aWindow
    }
    return self;
}

- (id)callWebScriptMethod:(CPString)methodName withArguments:(CPArray)args
{
    // Would using "with" be better here?
    if (typeof _window[methodName] == "function")
    {
        try {
            return _window[methodName].apply(args);
        } catch (e) {
        }
    }
    return undefined;
}

- (id)evaluateWebScript:(CPString)script
{
    try {
        return _window.eval(script);
    } catch (e) {
    }
    return undefined;
}

- (Window)window
{
    return _window;
}

@end