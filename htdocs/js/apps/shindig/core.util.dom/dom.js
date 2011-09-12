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
 * @class Provides general-purpose utility functions.
 */
gadgets.util = gadgets.util || {};

(function() {

  var XHTML_SPEC = 'http://www.w3.org/1999/xhtml';

  function attachAttributes(elem, opt_attribs) {
    var attribs = opt_attribs || {};
    for (var attrib in attribs) {
      if (attribs.hasOwnProperty(attrib)) {
        elem[attrib] = attribs[attrib];
      }
    }
  }

  function stringifyElement(tagName, opt_attribs) {
    var arr = ['<', tagName];
    var attribs = opt_attribs || {};
    for (var attrib in attribs) {
      if (attribs.hasOwnProperty(attrib)) {
        arr.push(' ');
        arr.push(attrib);
        arr.push('="');
        arr.push(gadgets.util.escapeString(attribs[attrib]));
        arr.push('"');
      }
    }
    arr.push('></');
    arr.push(tagName);
    arr.push('>');
    return arr.join('');
  }

  /**
   * Creates an HTML or XHTML element.
   * @param {string} tagName The type of element to construct.
   * @return {Element} The newly constructed element.
   */
  gadgets.util.createElement = function(tagName) {
    var element;
    if ((!document.body) || document.body.namespaceURI) {
      try {
        element = document.createElementNS(XHTML_SPEC, tagName);
      } catch (nonXmlDomException) {
      }
    }
    return element || document.createElement(tagName);
  };

  /**
   * Creates an HTML or XHTML iframe element with attributes.
   * @param {Object=} opt_attribs Optional set of attributes to attach. The
   * only working attributes are spelled the same way in XHTML attribute
   * naming (most strict, all-lower-case), HTML attribute naming (less strict,
   * case-insensitive), and JavaScript property naming (some properties named
   * incompatibly with XHTML/HTML).
   * @return {Element} The DOM node representing body.
   */
  gadgets.util.createIframeElement = function(opt_attribs) {
    var frame = gadgets.util.createElement('iframe');
    try {
      // TODO: provide automatic mapping to only set the needed
      // and JS-HTML-XHTML compatible subset through stringifyElement (just
      // 'name' and 'id', AFAIK). The values of the attributes will be
      // stringified should the stringifyElement code path be taken (IE)
      var tagString = stringifyElement('iframe', opt_attribs);
      var ieFrame = gadgets.util.createElement(tagString);
      if (ieFrame &&
          ((!frame) ||
           ((ieFrame.tagName == frame.tagName) &&
            (ieFrame.namespaceURI == frame.namespaceURI)))) {
        frame = ieFrame;
      }
    } catch (nonStandardCallFailed) {
    }
    attachAttributes(frame, opt_attribs);
    return frame;
  };

  /**
   * Gets the HTML or XHTML body element.
   * @return {Element} The DOM node representing body.
   */
  gadgets.util.getBodyElement = function() {
    if (document.body) {
      return document.body;
    }
    try {
      var xbodies = document.getElementsByTagNameNS(XHTML_SPEC, 'body');
      if (xbodies && (xbodies.length == 1)) {
        return xbodies[0];
      }
    } catch (nonXmlDomException) {
    }
    return document.documentElement || document;
  };

})();
