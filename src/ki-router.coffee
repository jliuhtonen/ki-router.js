###

Copyright 2012-2013 Mikko Apo

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

###

"use strict"

# TODO:
# - Assign multiple routes with one invocation
# - Ignore hash anchors
# - Check that bug from Anton
# Known bugs:
# Missing features:
# - four modes: transparentRouting, hashbangRouting, hashRouting and historyApiRouting
# - $("a").click does not register but $("a")[0].click does
# - more complete sinatra path parsing, JavascriptRouteParser
# - test suite
# - documentation
# Possible features
# - regexp special chars should be escaped
# - clarify when fallbackRoute is used or if it is needed
# - postExecutionListener gets access to exception during exec
# - executed function gets access to full matched information
# - relative url support is tricky to get right. What if application is served urls with splat?
# - querystring parameters as part of params. How should they interract with #! support?
# - form support, catch form submits (how would this work?) get / post?
# - chrome fails when converting plain url to hashbang url: %23, window.location.hash escaping
# - navigate
# - go
# Known issues:
# - hashbang urls don't work in a href tags -> won't fix, use /plain/urls
# - does not resolve situation hashbang url needs to be converted and both window.location.pathname and window.location.hash are defined

KiRouter = {}
KiRouter.version = '<version>'

if module?
  module.exports = KiRouter # for KiRouter = require 'KiRouterjs'
  KiRouter.KiRouter = KiRouter # for {KiRouter} = require 'KiRouterjs'
else
  if define? and define.amd?
    define [], -> KiRouter
  @KiRouter = KiRouter # otherwise for execution context

KiRouter.router = -> new KiRoutes()

class KiRoutes
  routes: []
  postExecutionListeners: []
  exceptionListeners: []
  debug: false
  previous: false
  paramVerifier: false
  renderCount: 0
  skipRouteHandlers: []

  log: =>
    if @debug && window.console && console && console.log
      if JSON.stringify
        console.log("ki-router: " + JSON.stringify(arguments))
      else
        console.log(arguments)
    return

  add: (urlPattern, fn, metadata) =>
    @routes.push({route: new SinatraRouteParser(urlPattern), fn: fn, urlPattern: urlPattern, metadata: metadata})

  exec: (path) =>
    if matched = @find(path)
      @execRoute(matched)

  execRoute: (matched) =>
    @log("Found route for", matched.path, " Calling function with params ", matched.params)
    @renderCount += 1
    try
      matched.result = matched.fn(matched.params)
      for listener in @postExecutionListeners
        listener(matched, @previous)
    catch error
      matched.error = error
      for exceptionListener in @exceptionListeners
        exceptionListener(matched, @previous)
      throw error
    @previous = matched
    return matched

  find: (path) =>
    for candidate in @routes
      if params = candidate.route.parse(path, @paramVerifier)
        return {params: params, route: candidate.matchedRoute, fn: candidate.fn, urlPattern: candidate.urlPattern, path: path, metadata: candidate.metadata}

  addSkipRouteHandler: (fn) =>
    @skipRouteHandlers.push(fn)

  addPostExecutionListener: (fn) =>
    @postExecutionListeners.push(fn)

  addExceptionListener: (fn) =>
    @exceptionListeners.push(fn)

  # Browser extensions

  pushStateSupport: history && history.pushState
  hashchangeSupport: "onhashchange" of window
  hashBaseUrl: false
  disableUrlUpdate: false
  fallbackRoute: false
  init: false
  initDone: false

  historyApiRouting: () =>
    @hashchangeSupport = false
    @transparentRouting()
    return

  transparentRouting: () =>
    @init = true
    try
      @attachClickListener()
      @attachLocationChangeListener()
      @renderInitialView()
      return
    finally
      @init = false
      @initDone = true

  hashbangRouting: () =>
    @pushStateSupport = false
    if !@hashchangeSupport
      throw new Error("No hashchange support!")
    @transparentRouting()
    return

  # Renders page based on current url
  renderInitialView: =>
    initialUrl = window.location.pathname
    if @pushStateSupport
      if window.location.hash.substring(0, 2) == "#!" && @find(window.location.hash.substring(2))
        initialUrl = window.location.hash.substring(2)
    else
      if @hashchangeSupport
        if window.location.hash.substring(0, 2) == "#!"
          initialUrl = window.location.hash.substring(2)
    @log("Rendering initial page")
    @renderUrl(initialUrl)
    return

  # Notices when browser goes back or forward in history
  attachLocationChangeListener: =>
    if @pushStateSupport
      @addListener window, "popstate", (event) =>
        href = window.location.pathname
        @log("Rendering popstate", href)
        @renderUrl(href)
        return
    else
      if @hashchangeSupport
        @addListener window, "hashchange", (event) =>
          if window.location.hash.substring(0, 2) == "#!"
            href = window.location.hash.substring(2)
            @log("Rendering hashchange", href)
            @renderUrl(href)
          return
    return

  renderUrl: (url) =>
    if ret = @exec(url)
      return ret
    else
      if @fallbackRoute
        return @fallbackRoute(url)
      else
        @log("Could not resolve route for", url)

  # Click listener catches clicks to A tag and processes the url if it matches known routes
  attachClickListener: =>
    if @pushStateSupport || @hashchangeSupport
      @addListener document, "click", (event) =>
        event = event || window.event
        target = event.target || event.srcElement
        if target
          @log("Checking if click event should be rendered")
          aTag = @findATag(target)
          if @checkIfOkToRender(event, aTag)
            href = aTag.attributes.href.nodeValue
            @log("Click event passed all checks")
            @renderUrlOrRedirect(href, event)
        return
    return

  renderUrlOrRedirect: (href, event) =>
    if @checkIfHashBaseUrlRedirectNeeded()
      @log("Using hashbang change to trigger rendering for", href)
      @disableEventDefault(event)
      window.location.href = @hashBaseUrl + "#!" + href
    else
      route = @find(href)
      if !route? || @skipRouteHandlers.some((handler) => handler(route, @previous))
        @log("Letting browser render url because no matching route", href)
        return
      if @disableUrlUpdate || @pushStateSupport
        @execRoute(route)
        @log("Rendered", href)
      @disableEventDefault(event)
      @updateUrl(href) unless @disableUrlUpdate
    return

  updateUrl: (href) =>
    if @pushStateSupport
      history.pushState({ }, document.title, href)
    else
      if @hashchangeSupport
        window.location.hash = "!" + href
    return

  checkIfHashBaseUrlRedirectNeeded: () =>
    !@pushStateSupport && @hashchangeSupport && @hashBaseUrl && @hashBaseUrl != window.location.pathname

  checkIfOkToRender: (event, aTag) =>
    @blog("- A tag", aTag) &&
    @blog("- Left mouse button click", @leftMouseButton(event)) &&
    @blog("- Not meta keys pressed", !@metakeyPressed(event)) &&
    @blog("- Target attribute is current window", @targetAttributeIsCurrentWindow(aTag)) &&
    @blog("- Link host same as current window", @targetHostSame(aTag))

  disableEventDefault: (ev) =>
    if ev
      if ev.preventDefault
        ev.preventDefault()
      else
        ev.returnValue = false
    return

  blog: (str, v) =>
    @log(str + ", result: " + v)
    v

  leftMouseButton: (event) =>
    event.which? && event.which == 1 || event.button == 0

  findATag: (target) =>
    while target
      if target.tagName == "A"
        return target
      target = target.parentElement
    false

  metakeyPressed: (event) =>
    (event.shiftKey || event.ctrlKey || event.altKey || event.metaKey)

  targetAttributeIsCurrentWindow: (aTag) =>
    if !aTag.attributes.target
      return true
    val = aTag.attributes.target.nodeValue
    if ["_blank", "_parent"].indexOf(val) != -1
      return false
    if val == "_self"
      return true
    if val == "_top"
      return window.self == window.top
    return val == window.name

  targetHostSame: (aTag) =>
    l = window.location
    targetUserName = @fixUsername(aTag.username)
    targetPort = @fixTargetPort(aTag.port, aTag.protocol)
    aTag.hostname == l.hostname && targetPort == l.port && aTag.protocol == l.protocol && targetUserName == @fixUsername(l.username) && aTag.password == aTag.password

  fixUsername: (username) =>
    # Firefox 26 sets aTag.username to "", other browsers use undefined
    if username == ""
      undefined
    else
      username

  # IE9 sets port to "443" even if protocol is https
  fixTargetPort: (port, protocol) =>
    protocolPorts =
      "http:" : "80"
      "https:" : "443"
    if port != "" && port == protocolPorts[protocol]
      ""
    else
      port

  addListener: (element, event, fn) =>
    if element.addEventListener  # W3C DOM
      element.addEventListener(event, fn, false);
    else if (element.attachEvent) # // IE DOM
      element.attachEvent("on"+event, fn);
    else
      throw new Error("addListener can not attach listeners!")

class SinatraRouteParser
  constructor: (route) ->
    @keys = []
    route = route.substring(1)
    segments = []
    routeItems = route.split("/")
    for segment in routeItems
      match = segment.match(/((:\w+)|\*)/)
      if match
        firstMatch = match[0]
        if firstMatch == "*"
          @keys.push "splat"
          segment = "(.*)"
        else
          @keys.push firstMatch.substring(1)
          segment = "([^\/?#]+)"
      else
        segment = segment.replace(".","\\.")
      segments.push segment
    pattern = "^/" + segments.join("/") + "$"
    #    console.log("Pattern", pattern)
    @pattern = new RegExp(pattern)
  parse: (path, paramVerify) =>
    matches = path.match(@pattern)
    #    console.log("Parse", path, matches)
    if matches
      i = 0
      ret = {}
      for match in matches.slice(1)
        if paramVerify && !paramVerify(match)
          return false # parameter did not pass verifier -> abort
        key = @keys[i]
        i+=1
        #        console.log("Found item", match, key)
        @append(ret, key, match)
      ret
  append: (h, key, value) ->
    if old = h[key]
      if !@typeIsArray(old)
        h[key] = [old]
      h[key].push(value)
    else
      h[key]=value
  typeIsArray: ( value ) ->
    value and
    typeof value is 'object' and
    value instanceof Array and
    typeof value.length is 'number' and
    typeof value.splice is 'function' and
    not ( value.propertyIsEnumerable 'length' )
