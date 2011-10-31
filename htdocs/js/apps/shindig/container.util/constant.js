/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership. The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */


/**
 * @fileoverview Constants used throughout common container.
 */


/**
 * Set up namespace.
 * @type {Object}
 */
osapi.container = {};


/**
 * Constants to key into gadget metadata state.
 * @const
 * @enum {string}
 */
osapi.container.MetadataParam = {
    LOCAL_EXPIRE_TIME: 'localExpireTimeMs',
    URL: 'url'
};


/**
 * Constants to key into gadget metadata response JSON.
 * @enum {string}
 */

osapi.container.MetadataResponse = {
  IFRAME_URL: 'iframeUrl',
  NEEDS_TOKEN_REFRESH: 'needsTokenRefresh',
  VIEWS: 'views',
  EXPIRE_TIME_MS: 'expireTimeMs',
  FEATURES: 'features',
  HEIGHT: 'height',
  MODULE_PREFS: 'modulePrefs',
  PREFERRED_HEIGHT: 'preferredHeight',
  PREFERRED_WIDTH: 'preferredWidth',
  RESPONSE_TIME_MS: 'responseTimeMs',
  WIDTH: 'width'
};


/**
 * Constants to key into gadget token response JSON.
 * @enum {string}
 */
osapi.container.TokenResponse = {
  TOKEN: 'token'
};


/**
 * Constants to key into timing response JSON.
 * @enum {string}
 */
osapi.container.NavigateTiming = {
  /** The gadget URL reporting this timing information. */
  URL: 'url',
  /** The gadget site ID reporting this timing information. */
  ID: 'id',
  /** Absolute time (ms) when gadget navigation is requested. */
  START: 'start',
  /** Time (ms) to receive XHR response time. In CC, for metadata and token. */
  XRT: 'xrt',
  /** Time (ms) to receive first byte. Typically timed at start of page. */
  SRT: 'srt',
  /** Time (ms) to load the DOM. Typically timed at end of page. */
  DL: 'dl',
  /** Time (ms) when body onload is called. */
  OL: 'ol',
  /** Time (ms) when page is ready for use. Typically happen after data XHR (ex:
   * calendar, email) is received/presented to users. Overridable by user.
   */
  PRT: 'prt'
};


/**
 * Constants to key into request renderParam JSON.
 * @enum {string}
 * @const
 */
osapi.container.RenderParam = {
    /** Allow gadgets to render in unspecified view. */
    ALLOW_DEFAULT_VIEW: 'allowDefaultView',

    /** Whether to enable cajole mode. */
    CAJOLE: 'cajole',

    /** Style class to associate to iframe. */
    CLASS: 'class',

    /** Whether to enable debugging mode. */
    DEBUG: 'debug',

    /** The starting gadget iframe height (in pixels). */
    HEIGHT: 'height',

    /** Whether to disable cache. */
    NO_CACHE: 'nocache',

    /** Whether to enable test mode. */
    TEST_MODE: 'testmode',

    /** The gadget user prefs to render with. */
    USER_PREFS: 'userPrefs',

    /** The view of gadget to render. */
    VIEW: 'view',

    /** The starting gadget iframe width (in pixels). */
    WIDTH: 'width'
};

/**
 * Constants to key into request viewParam JSON.
 * @enum {string}
 */
osapi.container.ViewParam = {
  VIEW: 'view'
};

/**
 * Constants to define lifecycle callback
 * @enum {string}
 */
osapi.container.CallbackType = {
    ON_PRELOADED: 'onPreloaded',
    ON_NAVIGATED: 'onNavigated',
    ON_CLOSED: 'onClosed',
    ON_UNLOADED: 'onUnloaded',
    ON_RENDER: 'onRender'
};
