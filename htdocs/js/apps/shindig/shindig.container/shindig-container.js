/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership. The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/**
 * @fileoverview Open Gadget Container.
 */

shindig.errors = {};
shindig.errors.SUBCLASS_RESPONSIBILITY = 'subclass responsibility';
shindig.errors.TO_BE_DONE = 'to be done';

/**
 * Calls an array of asynchronous functions and calls the continuation
 * function when all are done.
 * @param {Array} functions Array of asynchronous functions, each taking
 *     one argument that is the continuation function that handles the result
 *     That is, each function is something like the following:
 *     function(continuation) {
 *       // compute result asynchronously
 *       continuation(result);
 *     }.
 * @param {Function} continuation Function to call when all results are in.  It
 *     is pass an array of all results of all functions.
 * @param {Object} opt_this Optional object used as "this" when calling each
 *     function.
 */
shindig.callAsyncAndJoin = function(functions, continuation, opt_this) {
  var pending = functions.length;
  var results = [];
  for (var i = 0; i < functions.length; i++) {
    // we need a wrapper here because i changes and we need one index
    // variable per closure
    var wrapper = function(index) {
      var fn = functions[index];
      if (typeof fn === 'string') {
        fn = opt_this[fn];
      }
      fn.call(opt_this, function(result) {
        results[index] = result;
        if (--pending === 0) {
          continuation(results);
        }
      });
    };
    wrapper(i);
  }
};


// ----------
// Extensible

shindig.Extensible = function() {
};

/**
 * Sets the dependencies.
 * @param {Object} dependencies Object whose properties are set on this
 *     container as dependencies.
 */
shindig.Extensible.prototype.setDependencies = function(dependencies) {
  for (var p in dependencies) {
    this[p] = dependencies[p];
  }
};

/**
 * Returns a dependency given its name.
 * @param {String} name Name of dependency.
 * @return {Object} Dependency with that name or undefined if not found.
 */
shindig.Extensible.prototype.getDependencies = function(name) {
  return this[name];
};



// -------------
// UserPrefStore

/**
 * User preference store interface.
 * @constructor
 */
shindig.UserPrefStore = function() {
};

/**
 * Gets all user preferences of a gadget.
 * @param {Object} gadget Gadget object.
 * @return {Object} All user preference of given gadget.
 */
shindig.UserPrefStore.prototype.getPrefs = function(gadget) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

/**
 * Saves user preferences of a gadget in the store.
 * @param {Object} gadget Gadget object.
 * @param {Object} prefs User preferences.
 */
shindig.UserPrefStore.prototype.savePrefs = function(gadget) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};


// -------------
// DefaultUserPrefStore

/**
 * User preference store implementation.
 * TODO: Turn this into a real implementation that is production safe
 * @constructor
 */
shindig.DefaultUserPrefStore = function() {
  shindig.UserPrefStore.call(this);
};
shindig.DefaultUserPrefStore.inherits(shindig.UserPrefStore);

shindig.DefaultUserPrefStore.prototype.getPrefs = function(gadget) { };

shindig.DefaultUserPrefStore.prototype.savePrefs = function(gadget) { };


// -------------
// GadgetService

/**
 * Interface of service provided to gadgets for resizing gadgets,
 * setting title, etc.
 * @constructor
 */
shindig.GadgetService = function() {
};

shindig.GadgetService.prototype.setHeight = function(elementId, height) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

shindig.GadgetService.prototype.setTitle = function(gadget, title) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

shindig.GadgetService.prototype.setUserPref = function(id) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};


// ----------------
// IfrGadgetService

/**
 * Base implementation of GadgetService.
 * @constructor
 */
shindig.IfrGadgetService = function() {
  shindig.GadgetService.call(this);
  gadgets.rpc.register('resize_iframe', this.setHeight);
  gadgets.rpc.register('set_pref', this.setUserPref);
  gadgets.rpc.register('set_title', this.setTitle);
  gadgets.rpc.register('requestNavigateTo', this.requestNavigateTo);
  gadgets.rpc.register('requestSendMessage', this.requestSendMessage);
};

shindig.IfrGadgetService.inherits(shindig.GadgetService);

shindig.IfrGadgetService.prototype.setHeight = function(height) {
  if (height > shindig.container.maxheight_) {
    height = shindig.container.maxheight_;
  }

  var element = document.getElementById(this.f);
  if (element) {
    element.style.height = height + 'px';
  }
};

shindig.IfrGadgetService.prototype.setTitle = function(title) {
  var element = document.getElementById(this.f + '_title');
  if (element) {
    element.innerHTML = title.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  }
};

/**
 * Sets one or more user preferences
 * @param {String} editToken
 * @param {String} name Name of user preference.
 * @param {String} value Value of user preference
 * More names and values may follow.
 */
shindig.IfrGadgetService.prototype.setUserPref = function(editToken, name,
    value) {
  var id = shindig.container.gadgetService.getGadgetIdFromModuleId(this.f);
  var gadget = shindig.container.getGadget(id);
  for (var i = 1, j = arguments.length; i < j; i += 2) {
    this.userPrefs[arguments[i]].value = arguments[i + 1];
  }
  gadget.saveUserPrefs();
};

/**
 * Requests the container to send a specific message to the specified users.
 * @param {Array.<String>|String} recipients An ID, array of IDs, or a group reference;
 * the supported keys are VIEWER, OWNER, VIEWER_FRIENDS, OWNER_FRIENDS, or a
 * single ID within one of those groups.
 * @param {opensocial.Message} message The message to send to the specified users.
 * @param {Function} opt_callback The function to call once the request has been
 * processed; either this callback will be called or the gadget will be reloaded
 * from scratch.
 * @param {opensocial.NavigationParameters} opt_params The optional parameters
 * indicating where to send a user when a request is made, or when a request
 * is accepted; options are of type  NavigationParameters.DestinationType.
 */
shindig.IfrGadgetService.prototype.requestSendMessage = function(recipients,
    message, opt_callback, opt_params) {
  if (opt_callback) {
    window.setTimeout(function() {
      opt_callback(new opensocial.ResponseItem(
          null, null, opensocial.ResponseItem.Error.NOT_IMPLEMENTED, null));
    }, 0);
  }
};

/**
 * Navigates the page to a new url based on a gadgets requested view and
 * parameters.
 */
shindig.IfrGadgetService.prototype.requestNavigateTo = function(view,
    opt_params) {
  var id = shindig.container.gadgetService.getGadgetIdFromModuleId(this.f);
  var url = shindig.container.gadgetService.getUrlForView(view);

  if (opt_params) {
    var paramStr = gadgets.json.stringify(opt_params);
    if (paramStr.length > 0) {
      url += '&appParams=' + encodeURIComponent(paramStr);
    }
  }

  if (url && document.location.href.indexOf(url) == -1) {
    document.location.href = url;
  }
};

/**
 * This is a silly implementation that will need to be overriden by almost all
 * real containers.
 * TODO: Find a better default for this function
 *
 * @param {string} view The view name to get the url for.
 */
shindig.IfrGadgetService.prototype.getUrlForView = function(view) {
  if (view === 'canvas') {
    return '/canvas';
  } else if (view === 'profile') {
    return '/profile';
  } else {
    return null;
  }
};

shindig.IfrGadgetService.prototype.getGadgetIdFromModuleId = function(
    moduleId) {
  // Quick hack to extract the gadget id from module id
  return parseInt(moduleId.match(/_([0-9]+)$/)[1], 10);
};


// -------------
// LayoutManager

/**
 * Layout manager interface.
 * @constructor
 */
shindig.LayoutManager = function() {
};

/**
 * Gets the HTML element that is the chrome of a gadget into which the content
 * of the gadget can be rendered.
 * @param {Object} gadget Gadget instance.
 * @return {Object} HTML element that is the chrome for the given gadget.
 */
shindig.LayoutManager.prototype.getGadgetChrome = function(gadget) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

// -------------------
// StaticLayoutManager

/**
 * Static layout manager where gadget ids have a 1:1 mapping to chrome ids.
 * @constructor
 */
shindig.StaticLayoutManager = function() {
  shindig.LayoutManager.call(this);
};

shindig.StaticLayoutManager.inherits(shindig.LayoutManager);

/**
 * Sets chrome ids, whose indexes are gadget instance ids (starting from 0).
 * @param {Array} gadgetChromeIds Gadget id to chrome id map.
 */
shindig.StaticLayoutManager.prototype.setGadgetChromeIds =
    function(gadgetChromeIds) {
  this.gadgetChromeIds_ = gadgetChromeIds;
};

shindig.StaticLayoutManager.prototype.getGadgetChrome = function(gadget) {
  var chromeId = this.gadgetChromeIds_[gadget.id];
  return chromeId ? document.getElementById(chromeId) : null;
};


// ----------------------
// FloatLeftLayoutManager

/**
 * FloatLeft layout manager where gadget ids have a 1:1 mapping to chrome ids.
 * @constructor
 * @param {String} layoutRootId Id of the element that is the parent of all
 *     gadgets.
 */
shindig.FloatLeftLayoutManager = function(layoutRootId) {
  shindig.LayoutManager.call(this);
  this.layoutRootId_ = layoutRootId;
};

shindig.FloatLeftLayoutManager.inherits(shindig.LayoutManager);

shindig.FloatLeftLayoutManager.prototype.getGadgetChrome =
    function(gadget) {
  var layoutRoot = document.getElementById(this.layoutRootId_);
  if (layoutRoot) {
    var chrome = document.createElement('div');
    chrome.className = 'gadgets-gadget-chrome';
    chrome.style.cssFloat = 'left';
    layoutRoot.appendChild(chrome);
    return chrome;
  } else {
    return null;
  }
};


// ------
// Gadget

/**
 * Creates a new instance of gadget.  Optional parameters are set as instance
 * variables.
 * @constructor
 * @param {Object} params Parameters to set on gadget.  Common parameters:
 *    "specUrl": URL to gadget specification
 *    "private": Whether gadget spec is accessible only privately, which means
 *        browser can load it but not gadget server
 *    "spec": Gadget Specification in XML
 *    "userPrefs": a javascript object containing attribute value pairs of user
 *        preferences for this gadget with the value being a preference object
 *    "viewParams": a javascript object containing attribute value pairs
 *        for this gadgets
 *    "secureToken": an encoded token that is passed on the URL hash
 *    "hashData": Query-string like data that will be added to the
 *        hash portion of the URL.
 *    "specVersion": a hash value used to add a v= param to allow for better caching
 *    "title": the default title to use for the title bar.
 *    "height": height of the gadget
 *    "width": width of the gadget
 *    "debug": send debug=1 to the gadget server, gets us uncompressed
 *        javascript.
 */
shindig.Gadget = function(params) {
  this.userPrefs = {};

  if (params) {
    for (var name in params) if (params.hasOwnProperty(name)) {
      this[name] = params[name];
    }
  }
  if (!this.secureToken) {
    // Assume that the default security token implementation is
    // in use on the server.
    this.secureToken = 'john.doe:john.doe:appid:cont:url:0:default';
  }
};

shindig.Gadget.prototype.setServerBase = function(url) {
  this.serverBase_ = url;
}

shindig.Gadget.prototype.getServerBase = function() {
  return this.serverBase_;
};


shindig.Gadget.prototype.getUserPrefs = function() {
  return this.userPrefs;
};

shindig.Gadget.prototype.saveUserPrefs = function() {
  shindig.container.userPrefStore.savePrefs(this);
};

shindig.Gadget.prototype.getUserPrefValue = function(name) {
  var pref = this.userPrefs[name];
  return typeof(pref.value) != 'undefined' && pref.value != null ?
      pref.value : pref['default'];
};

shindig.Gadget.prototype.render = function(chrome) {
  if (chrome) {
    var gadget = this;
    this.getContent(function(content) {
      chrome.innerHTML = content;
      gadget.finishRender(chrome);
    });
  }
};

shindig.Gadget.prototype.getContent = function(continuation) {
  shindig.callAsyncAndJoin([
    'getTitleBarContent', 'getUserPrefsDialogContent',
    'getMainContent'], function(results) {
    continuation(results.join(''));
  }, this);
};

/**
 * Gets title bar content asynchronously or synchronously.
 * @param {Function} continuation Function that handles title bar content as
 *     the one and only argument.
 */
shindig.Gadget.prototype.getTitleBarContent = function(continuation) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

/**
 * Gets user preferences dialog content asynchronously or synchronously.
 * @param {Function} continuation Function that handles user preferences
 *     content as the one and only argument.
 */
shindig.Gadget.prototype.getUserPrefsDialogContent = function(continuation) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

/**
 * Gets gadget content asynchronously or synchronously.
 * @param {Function} continuation Function that handles gadget content as
 *     the one and only argument.
 */
shindig.Gadget.prototype.getMainContent = function(continuation) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

shindig.Gadget.prototype.finishRender = function(chrome) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

/*
 * Gets additional parameters to append to the iframe url
 * Override this method if you need any custom params.
 */
shindig.Gadget.prototype.getAdditionalParams = function() {
  return '';
};


// ---------
// IfrGadget

shindig.BaseIfrGadget = function(opt_params) {
  shindig.Gadget.call(this, opt_params);
  
  if (!this.serverBase_){
    this.serverBase_ = '/gadgets/'; // default gadget server
  } else if (this.serverBase_.indexOf('/gadgets')<0) {
    this.serverBase_ += '/gadgets/';
  }
  this.queryIfrGadgetType_();
};

shindig.BaseIfrGadget.inherits(shindig.Gadget);

shindig.BaseIfrGadget.prototype.GADGET_IFRAME_PREFIX_ = 'remote_iframe_';

shindig.BaseIfrGadget.prototype.CONTAINER = 'default';

shindig.BaseIfrGadget.prototype.cssClassGadget = 'gadgets-gadget';
shindig.BaseIfrGadget.prototype.cssClassTitleBar = 'gadgets-gadget-title-bar';
shindig.BaseIfrGadget.prototype.cssClassTitle = 'gadgets-gadget-title';
shindig.BaseIfrGadget.prototype.cssClassTitleButtonBar =
    'gadgets-gadget-title-button-bar';
shindig.BaseIfrGadget.prototype.cssClassGadgetUserPrefsDialog =
    'gadgets-gadget-user-prefs-dialog';
shindig.BaseIfrGadget.prototype.cssClassGadgetUserPrefsDialogActionBar =
    'gadgets-gadget-user-prefs-dialog-action-bar';
shindig.BaseIfrGadget.prototype.cssClassTitleButton = 'gadgets-gadget-title-button';
shindig.BaseIfrGadget.prototype.cssClassGadgetContent = 'gadgets-gadget-content';
shindig.BaseIfrGadget.prototype.rpcToken = (0x7FFFFFFF * Math.random()) | 0;
shindig.BaseIfrGadget.prototype.rpcRelay = '../container/rpc_relay.html';

shindig.BaseIfrGadget.prototype.getTitleBarContent = function(continuation) {
  var settingsButton = this.hasViewablePrefs_() ?
      '<a href="#" onclick="shindig.container.getGadget(' + this.id +
          ').handleOpenUserPrefsDialog();return false;" class="' + this.cssClassTitleButton +
          '">settings</a> '
      : '';
  continuation('<div id="' + this.cssClassTitleBar + '-' + this.id +
      '" class="' + this.cssClassTitleBar + '"><span id="' +
      this.getIframeId() + '_title" class="' +
      this.cssClassTitle + '">' + (this.title ? this.title : 'Title') + '</span> | <span class="' +
      this.cssClassTitleButtonBar + '">' + settingsButton +
      '<a href="#" onclick="shindig.container.getGadget(' + this.id +
      ').handleToggle();return false;" class="' + this.cssClassTitleButton +
      '">toggle</a></span></div>');
};

shindig.BaseIfrGadget.prototype.getUserPrefsDialogContent = function(continuation) {
  continuation('<div id="' + this.getUserPrefsDialogId() + '" class="' +
      this.cssClassGadgetUserPrefsDialog + '"></div>');
};



shindig.BaseIfrGadget.prototype.getMainContent = function(continuation) {
  // proper sub-class has not been mixed-in yet
  var gadget = this;
  window.setTimeout(function() {
    gadget.getMainContent(continuation);
  }, 0);
};

shindig.BaseIfrGadget.prototype.getIframeId = function() {
  return this.GADGET_IFRAME_PREFIX_ + this.id;
};

shindig.BaseIfrGadget.prototype.getUserPrefsDialogId = function() {
  return this.getIframeId() + '_userPrefsDialog';
};

shindig.BaseIfrGadget.prototype.getUserPrefsParams = function() {
  var params = '';
  for (var name in this.getUserPrefs()) {
    params += '&up_' + encodeURIComponent(name) + '=' +
        encodeURIComponent(this.getUserPrefValue(name));
  }
  return params;
};

shindig.BaseIfrGadget.prototype.handleToggle = function() {
  var gadgetIframe = document.getElementById(this.getIframeId());
  if (gadgetIframe) {
    var gadgetContent = gadgetIframe.parentNode;
    var display = gadgetContent.style.display;
    gadgetContent.style.display = display ? '' : 'none';
  }
};


shindig.BaseIfrGadget.prototype.hasViewablePrefs_ = function() {
  for (var name in this.getUserPrefs()) {
    var pref = this.userPrefs[name];
    if (pref.type != 'hidden') {
      return true;
    }
  }
  return false;
};


shindig.BaseIfrGadget.prototype.handleOpenUserPrefsDialog = function() {
  if (this.userPrefsDialogContentLoaded) {
    this.showUserPrefsDialog();
  } else {
    var gadget = this;
    var igCallbackName = 'ig_callback_' + this.id;
    window[igCallbackName] = function(userPrefsDialogContent) {
      gadget.userPrefsDialogContentLoaded = true;
      gadget.buildUserPrefsDialog(userPrefsDialogContent);
      gadget.showUserPrefsDialog();
    };

    var script = document.createElement('script');
    script.src = 'http://www.gmodules.com/ig/gadgetsettings?mid=' + this.id +
        '&output=js' + this.getUserPrefsParams() + '&url=' + this.specUrl;
    document.body.appendChild(script);
  }
};

shindig.BaseIfrGadget.prototype.buildUserPrefsDialog = function(content) {
  var userPrefsDialog = document.getElementById(this.getUserPrefsDialogId());
  userPrefsDialog.innerHTML = content +
      '<div class="' + this.cssClassGadgetUserPrefsDialogActionBar +
      '"><input type="button" value="Save" onclick="shindig.container.getGadget(' +
      this.id + ').handleSaveUserPrefs()"> <input type="button" value="Cancel" onclick="shindig.container.getGadget(' +
      this.id + ').handleCancelUserPrefs()"></div>';
  userPrefsDialog.childNodes[0].style.display = '';
};

shindig.BaseIfrGadget.prototype.showUserPrefsDialog = function(opt_show) {
  var userPrefsDialog = document.getElementById(this.getUserPrefsDialogId());
  userPrefsDialog.style.display = (opt_show || opt_show === undefined)
      ? '' : 'none';
};

shindig.BaseIfrGadget.prototype.hideUserPrefsDialog = function() {
  this.showUserPrefsDialog(false);
};

shindig.BaseIfrGadget.prototype.handleSaveUserPrefs = function() {
  this.hideUserPrefsDialog();

  var numFields = document.getElementById('m_' + this.id +
      '_numfields').value;
  for (var i = 0; i < numFields; i++) {
    var input = document.getElementById('m_' + this.id + '_' + i);
    var userPrefNamePrefix = 'm_' + this.id + '_up_';
    var userPrefName = input.name.substring(userPrefNamePrefix.length);
    var userPrefValue = input.value;
    this.userPrefs[userPrefName].value = userPrefValue;
  }

  this.saveUserPrefs();
  this.refresh();
};

shindig.BaseIfrGadget.prototype.handleCancelUserPrefs = function() {
  this.hideUserPrefsDialog();
};

shindig.BaseIfrGadget.prototype.refresh = function() {
  var iframeId = this.getIframeId();
  // we have to add a random value to the iframe url because otherwise
  // some browsers would not refresh the since the iframe src would remain the
  // same
  document.getElementById(iframeId).src = this.getIframeUrl(Math.random());
};

shindig.BaseIfrGadget.prototype.queryIfrGadgetType_ = function() {
  // Get the gadget metadata and check if the gadget requires the 'pubsub-2'
  // feature.  If so, then we use OpenAjax Hub in order to create and manage
  // the iframe.  Otherwise, we create the iframe ourselves.
  var request = {
    context: {
      country: 'default',
      language: 'default',
      view: 'default',
      container: 'default'
    },
    gadgets: [{
      url: this.specUrl,
      moduleId: 1
    }]
  };

  var makeRequestParams = {
    'CONTENT_TYPE' : 'JSON',
    'METHOD' : 'POST',
    'POST_DATA' : gadgets.json.stringify(request)
  };

  var url = this.serverBase_ + 'metadata?st=' + this.secureToken;

  gadgets.io.makeNonProxiedRequest(url,
      handleJSONResponse,
      makeRequestParams,
      {'Content-Type':'application/javascript'}
  );

  var gadget = this;
  function handleJSONResponse(obj) {
    var requiresPubSub2 = false;
    var arr = obj.data.gadgets[0].features;
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] === 'pubsub-2') {
        requiresPubSub2 = true;
        break;
      }
    }
    var subClass = requiresPubSub2 ? shindig.OAAIfrGadget : shindig.IfrGadget;
    for (var name in subClass) if (subClass.hasOwnProperty(name)) {
      gadget[name] = subClass[name];
    }
  }
};

// ---------
// IfrGadget

shindig.IfrGadget = {
  getMainContent: function(continuation) {
    var iframeId = this.getIframeId();
    gadgets.rpc.setRelayUrl(iframeId, this.serverBase_ + this.rpcRelay);
    gadgets.rpc.setAuthToken(iframeId, this.rpcToken);
    continuation('<div class="' + this.cssClassGadgetContent + '"><iframe id="' +
        iframeId + '" name="' + iframeId + '" class="' + this.cssClassGadget +
        '" src="about:blank' +
        '" frameborder="no" scrolling="no"' +
        (this.height ? ' height="' + this.height + '"' : '') +
        (this.width ? ' width="' + this.width + '"' : '') +
        '></iframe></div>');
  },

  finishRender: function(chrome) {
    window.frames[this.getIframeId()].location = this.getIframeUrl();
  },

  getIframeUrl: function(random) {
    return this.serverBase_ + 'ifr?' +
        'container=' + this.CONTAINER +
        '&mid=' + this.id +
        '&nocache=' + shindig.container.nocache_ +
        '&country=' + shindig.container.country_ +
        '&lang=' + shindig.container.language_ +
        '&view=' + shindig.container.view_ +
        (this.specVersion ? '&v=' + this.specVersion : '') +
        (shindig.container.parentUrl_ ? '&parent=' + encodeURIComponent(shindig.container.parentUrl_) : '') +
        (this.debug ? '&debug=1' : '') +
        this.getAdditionalParams() +
        this.getUserPrefsParams() +
        (this.secureToken ? '&st=' + this.secureToken : '') +
        '&url=' + encodeURIComponent(this.specUrl) +
        (this.viewParams ?
            '&view-params=' + encodeURIComponent(gadgets.json.stringify(this.viewParams)) : '') +
        (random ? '&r=' + random : '') +
        '#rpctoken=' + this.rpcToken +
        (this.hashData ? '&' + this.hashData : '');
  }
};


// ---------
// OAAIfrGadget

shindig.OAAIfrGadget = {
  getMainContent: function(continuation) {
    continuation('<div id="' + this.cssClassGadgetContent + '-' + this.id +
        '" class="' + this.cssClassGadgetContent + '"></div>');
  },

  finishRender: function(chrome) {
    var iframeAttrs = {
      className: this.cssClassGadget,
      frameborder: 'no',
      scrolling: 'no'
    };
    if (this.height) {
      iframeAttrs.height = this.height;
    }
    if (this.width) {
      iframeAttrs.width = this.width;
    }

    new OpenAjax.hub.IframeContainer(
        gadgets.pubsub2router.hub,
        this.getIframeId(),
        {
          Container: {
            onSecurityAlert: function(source, alertType) {
              gadgets.error('Security error for container ' + source.getClientID() + ' : ' + alertType);
              source.getIframe().src = 'about:blank';
              // for debugging
              //          },
              //          onConnect: function( container ) {
              //            gadgets.log("++ connected: " + container.getClientID());
            }
          },
          IframeContainer: {
            parent: document.getElementById(this.cssClassGadgetContent + '-' + this.id),
            uri: this.getIframeUrl(),
            tunnelURI: shindig.uri(this.serverBase_ + this.rpcRelay).resolve(shindig.uri(window.location.href)),
            iframeAttrs: iframeAttrs
          }
        }
    );
  },

  getIframeUrl: function(random) {
    return this.serverBase_ + 'ifr?' +
        'container=' + this.CONTAINER +
        '&mid=' + this.id +
        '&nocache=' + shindig.container.nocache_ +
        '&country=' + shindig.container.country_ +
        '&lang=' + shindig.container.language_ +
        '&view=' + shindig.container.view_ +
        (this.specVersion ? '&v=' + this.specVersion : '') +
        //      (shindig.container.parentUrl_ ? '&parent=' + encodeURIComponent(shindig.container.parentUrl_) : '') +
        (this.debug ? '&debug=1' : '') +
        this.getAdditionalParams() +
        this.getUserPrefsParams() +
        (this.secureToken ? '&st=' + this.secureToken : '') +
        '&url=' + encodeURIComponent(this.specUrl) +
        //      '#rpctoken=' + this.rpcToken +
        (this.viewParams ?
            '&view-params=' + encodeURIComponent(gadgets.json.stringify(this.viewParams)) : '') +
        (random ? '&r=' + random : '') +
        //      (this.hashData ? '&' + this.hashData : '');
        (this.hashData ? '#' + this.hashData : '');
  }
};


// ---------
// Container

/**
 * Container interface.
 * @constructor
 */
shindig.Container = function() {
  this.gadgets_ = {};
  this.parentUrl_ = 'http://' + document.location.host;
  this.country_ = 'ALL';
  this.language_ = 'ALL';
  this.view_ = 'default';
  this.nocache_ = 1;

  // signed max int
  this.maxheight_ = 0x7FFFFFFF;
};

shindig.Container.inherits(shindig.Extensible);

/**
 * Known dependencies:
 *     gadgetClass: constructor to create a new gadget instance
 *     userPrefStore: instance of a subclass of shindig.UserPrefStore
 *     gadgetService: instance of a subclass of shindig.GadgetService
 *     layoutManager: instance of a subclass of shindig.LayoutManager
 */

shindig.Container.prototype.gadgetClass = shindig.Gadget;

shindig.Container.prototype.userPrefStore = new shindig.DefaultUserPrefStore();

shindig.Container.prototype.gadgetService = new shindig.GadgetService();

shindig.Container.prototype.layoutManager =
    new shindig.StaticLayoutManager();

shindig.Container.prototype.setParentUrl = function(url) {
  this.parentUrl_ = url;
};

shindig.Container.prototype.setCountry = function(country) {
  this.country_ = country;
};

shindig.Container.prototype.setNoCache = function(nocache) {
  this.nocache_ = nocache;
};

shindig.Container.prototype.setLanguage = function(language) {
  this.language_ = language;
};

shindig.Container.prototype.setView = function(view) {
  this.view_ = view;
};

shindig.Container.prototype.setMaxHeight = function(maxheight) {
  this.maxheight_ = maxheight;
};

shindig.Container.prototype.getGadgetKey_ = function(instanceId) {
  return 'gadget_' + instanceId;
};

shindig.Container.prototype.getGadget = function(instanceId) {
  return this.gadgets_[this.getGadgetKey_(instanceId)];
};

shindig.Container.prototype.createGadget = function(opt_params) {
  return new this.gadgetClass(opt_params);
};

shindig.Container.prototype.addGadget = function(gadget) {
  gadget.id = this.getNextGadgetInstanceId();
  this.gadgets_[this.getGadgetKey_(gadget.id)] = gadget;
};

shindig.Container.prototype.addGadgets = function(gadgets) {
  for (var i = 0; i < gadgets.length; i++) {
    this.addGadget(gadgets[i]);
  }
};

/**
 * Renders all gadgets in the container.
 */
shindig.Container.prototype.renderGadgets = function() {
  for (var key in this.gadgets_) {
    this.renderGadget(this.gadgets_[key]);
  }
};

/**
 * Renders a gadget.  Gadgets are rendered inside their chrome element.
 * @param {Object} gadget Gadget object.
 */
shindig.Container.prototype.renderGadget = function(gadget) {
  throw Error(shindig.errors.SUBCLASS_RESPONSIBILITY);
};

shindig.Container.prototype.nextGadgetInstanceId_ = 0;

shindig.Container.prototype.getNextGadgetInstanceId = function() {
  return this.nextGadgetInstanceId_++;
};

/**
 * Refresh all the gadgets in the container.
 */
shindig.Container.prototype.refreshGadgets = function() {
  for (var key in this.gadgets_) {
    this.gadgets_[key].refresh();
  }
};


// ------------
// IfrContainer

/**
 * Container that renders gadget using ifr.
 * @constructor
 */
shindig.IfrContainer = function() {
  shindig.Container.call(this);
};

shindig.IfrContainer.inherits(shindig.Container);

shindig.IfrContainer.prototype.gadgetClass = shindig.BaseIfrGadget;

shindig.IfrContainer.prototype.gadgetService = new shindig.IfrGadgetService();

shindig.IfrContainer.prototype.setParentUrl = function(url) {
  if (!url.match(/^http[s]?:\/\//)) {
    url = document.location.href.match(/^[^?#]+\//)[0] + url;
  }

  this.parentUrl_ = url;
};

/**
 * Renders a gadget using ifr.
 * @param {Object} gadget Gadget object.
 */
// shindig.IfrContainer.prototype.renderGadget = function(gadget) {
//   var chrome = this.layoutManager.getGadgetChrome(gadget);
//   gadget.render(chrome);
// };
// 
// function init(config) {
//     var sbase = config['shindig-container'];
//     shindig.Gadget.prototype.setServerBase(sbase.serverBase);
// }

// We do run this in the container mode in the new common container
// if (gadgets.config) {
//   gadgets.config.register('shindig-container', null, init);
// };

/**
 * Default container.
 */
// shindig.container = new shindig.IfrContainer();
