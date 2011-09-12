/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

/**
 * @fileoverview General purpose utilities that gadgets can use.
 */


/**
 * @class Provides a thin method for parsing url parameters.
 */
gadgets.util = gadgets.util || {};

(function() {
  var parameters = null;

  /**
   * Parses URL parameters into an object.
   * @param {string} url - the url parameters to parse.
   * @return {Array.<string>} The parameters as an array.
   */
  function parseUrlParams(url) {
    // Get settings from url, 'hash' takes precedence over 'search' component
    // don't use document.location.hash due to browser differences.
    var query;
    var queryIdx = url.indexOf('?');
    var hashIdx = url.indexOf('#');
    if (hashIdx === -1) {
      query = url.substr(queryIdx + 1);
    } else {
      // essentially replaces "#" with "&"
      query = [url.substr(queryIdx + 1, hashIdx - queryIdx - 1), '&',
               url.substr(hashIdx + 1)].join('');
    }
    return query.split('&');
  }

  /**
   * Gets the URL parameters.
   *
   * @param {string=} opt_url Optional URL whose parameters to parse.
   *                         Defaults to window's current URL.
   * @return {Object} Parameters passed into the query string.
   * @private Implementation detail.
   */
  gadgets.util.getUrlParameters = function(opt_url) {
    var no_opt_url = typeof opt_url === 'undefined';
    if (parameters !== null && no_opt_url) {
      // "parameters" is a cache of current window params only.
      return parameters;
    }
    var parsed = {};
    var pairs = parseUrlParams(opt_url || document.location.href);
    var unesc = window.decodeURIComponent ? decodeURIComponent : unescape;
    for (var i = 0, j = pairs.length; i < j; ++i) {
      var pos = pairs[i].indexOf('=');
      if (pos === -1) {
        continue;
      }
      var argName = pairs[i].substring(0, pos);
      var value = pairs[i].substring(pos + 1);
      // difference to IG_Prefs, is that args doesn't replace spaces in
      // argname. Unclear on if it should do:
      // argname = argname.replace(/\+/g, " ");
      value = value.replace(/\+/g, ' ');
      try {
        parsed[argName] = unesc(value);
      } catch (e) {
        // Undecodable/invalid value; ignore.
      }
    }
    if (no_opt_url) {
      // Cache current-window params in parameters var.
      parameters = parsed;
    }
    return parsed;
  };
})();

// Initialize url parameters so that hash data is pulled in before it can be
// altered by a click.
gadgets.util.getUrlParameters();
