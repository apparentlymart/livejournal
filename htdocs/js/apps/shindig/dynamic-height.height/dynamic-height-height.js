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
 * @fileoverview This library augments gadgets.window with functionality
 * to change the height of a gadget dynamically.
 */

/**
 * @static
 * @class Provides operations for getting information about the window the
 *        gadget is placed in.
 * @name gadgets.window
 */
gadgets.window = gadgets.window || {};

(function() {

  /**
   * Parse out the value (specified in px) for a CSS attribute of an element.
   *
   * @param {Element} elem the element with the attribute to look for.
   * @param {string} attr the CSS attribute name of interest.
   * @return {number} the value of the px attr of the elem.
   * @private
   */
  function parseIntFromElemPxAttribute(elem, attr) {
    var style = window.getComputedStyle(elem, '');
    var value = style.getPropertyValue(attr);
    value.match(/^([0-9]+)/);
    return parseInt(RegExp.$1, 10);
  }

  /**
   * For Webkit-based browsers, calculate the height of the gadget iframe by
   * iterating through all elements in the gadget, starting with the body tag.
   * It is not sufficient to only account body children elements, because
   * CSS style position "float" may place a child element outside of the
   * containing parent element. Not counting "float" elements may lead to
   * undercounting.
   *
   * @return {number} the height of the gadget.
   * @private
   */
  function getHeightForWebkit() {
    var result = 0;
    var queue = [document.body];

    while (queue.length > 0) {
      var elem = queue.shift();
      var children = elem.childNodes;

      /*
       * Here, we are checking if we are a container that clips its overflow wit h
       * a specific height, because if so, we should ignore children
       */

      // check that elem is actually an element, could be a text node otherwise
      if (typeof elem.style !== 'undefined') {
        // Get the overflowY value, looking in the computed style if necessary
        var overflowY = elem.style['overflowY'];
        if (!overflowY) {
          var css = document.defaultView.getComputedStyle(elem, null);
          overflowY = css ? css['overflowY'] : null;
        }

        // The only non-clipping values of overflow is 'visible'. We assume that 'inherit'
        // is also non-clipping at the moment, but should we check this?
        if (overflowY != 'visible' && overflowY != 'inherit') {
          // Make sure this element explicitly specifies a height
          var height = elem.style['height'];
          if (!height) {
            var css = document.defaultView.getComputedStyle(elem, null);
            height = css ? css['height'] : '';
          }
          if (height.length > 0 && height != 'auto') {
            // We can safely ignore the children of this element,
            // so move onto the next in the queue
            continue;
          }
        }
      }

      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (typeof child.offsetTop !== 'undefined' &&
            typeof child.offsetHeight !== 'undefined') {
          // offsetHeight already accounts for border-bottom, padding-bottom.
          var bottom = child.offsetTop + child.offsetHeight +
              parseIntFromElemPxAttribute(child, 'margin-bottom');
          result = Math.max(result, bottom);
        }
        queue.push(child);
      }
    }

    // Add border, padding and margin of the containing body.
    return result +
        parseIntFromElemPxAttribute(document.body, 'border-bottom') +
        parseIntFromElemPxAttribute(document.body, 'margin-bottom') +
        parseIntFromElemPxAttribute(document.body, 'padding-bottom');
  }

  /**
   * Adjusts the gadget height
   * @param {number=} opt_height An optional preferred height in pixels. If not
   *     specified, will attempt to fit the gadget to its content.
   * @member gadgets.window
   */

  /**
   * Calculate inner content height is hard and different between
   * browsers rendering in Strict vs. Quirks mode.  We use a combination of
   * three properties within document.body and document.documentElement:
   * - scrollHeight
   * - offsetHeight
   * - clientHeight
   * These values differ significantly between browsers and rendering modes.
   * But there are patterns.  It just takes a lot of time and persistence
   * to figure out.
   */
  gadgets.window.getHeight = function() {
    // Get the height of the viewport
    var vh = gadgets.window.getViewportDimensions().height;
    var body = document.body;
    var docEl = document.documentElement;
    if (document.compatMode === 'CSS1Compat' && docEl.scrollHeight) {
      // In Strict mode:
      // The inner content height is contained in either:
      //    document.documentElement.scrollHeight
      //    document.documentElement.offsetHeight
      // Based on studying the values output by different browsers,
      // use the value that's NOT equal to the viewport height found above.
      return docEl.scrollHeight !== vh ?
          docEl.scrollHeight : docEl.offsetHeight;
    } else if (navigator.userAgent.indexOf('AppleWebKit') >= 0) {
      // In Webkit:
      // Property scrollHeight and offsetHeight will only increase in value.
      // This will incorrectly calculate reduced height of a gadget
      // (ie: made smaller).
      return getHeightForWebkit();
    } else if (body && docEl) {
      // In Quirks mode:
      // documentElement.clientHeight is equal to documentElement.offsetHeight
      // except in IE.  In most browsers, document.documentElement can be used
      // to calculate the inner content height.
      // However, in other browsers (e.g. IE), document.body must be used
      // instead.  How do we know which one to use?
      // If document.documentElement.clientHeight does NOT equal
      // document.documentElement.offsetHeight, then use document.body.
      var sh = docEl.scrollHeight;
      var oh = docEl.offsetHeight;
      if (docEl.clientHeight !== oh) {
        sh = body.scrollHeight;
        oh = body.offsetHeight;
      }

      // Detect whether the inner content height is bigger or smaller
      // than the bounding box (viewport).  If bigger, take the larger
      // value.  If smaller, take the smaller value.
      if (sh > vh) {
        // Content is larger
        return sh > oh ? sh : oh;
      } else {
        // Content is smaller
        return sh < oh ? sh : oh;
      }
    }
  };

  /**
   * Parse out the value (specified in px) for a CSS attribute of an element.
   *
   * @param {Element} elem the element with the attribute to look for.
   * @param {string} attr the CSS attribute name of interest.
   * @return {number} the value of the px attr of the elem.
   * @private
   */
  function parseIntFromElemPxAttribute(elem, attr) {
    var style = window.getComputedStyle(elem, '');
    var value = style.getPropertyValue(attr);
    value.match(/^([0-9]+)/);
    return parseInt(RegExp.$1, 10);
  }

  /**
   * For Webkit-based browsers, calculate the height of the gadget iframe by
   * iterating through all elements in the gadget, starting with the body tag.
   * It is not sufficient to only account body children elements, because
   * CSS style position "float" may place a child element outside of the
   * containing parent element. Not counting "float" elements may lead to
   * undercounting.
   *
   * @return {number} the height of the gadget.
   * @private
   */
  function getHeightForWebkit() {
    var result = 0;
    var queue = [document.body];

    while (queue.length > 0) {
      var elem = queue.shift();
      var children = elem.childNodes;

      /*
       * Here, we are checking if we are a container that clips its overflow wit h
       * a specific height, because if so, we should ignore children
       */

      // check that elem is actually an element, could be a text node otherwise
      if (typeof elem.style !== 'undefined') {
        // Get the overflowY value, looking in the computed style if necessary
        var overflowY = elem.style['overflowY'];
        if (!overflowY) {
          var css = document.defaultView.getComputedStyle(elem, null);
          overflowY = css ? css['overflowY'] : null;
        }

        // The only non-clipping values of overflow is 'visible'. We assume that 'inherit'
        // is also non-clipping at the moment, but should we check this?
        if (overflowY != 'visible' && overflowY != 'inherit') {
          // Make sure this element explicitly specifies a height
          var height = elem.style['height'];
          if (!height) {
            var css = document.defaultView.getComputedStyle(elem, null);
            height = css ? css['height'] : '';
          }
          if (height.length > 0 && height != 'auto') {
            // We can safely ignore the children of this element,
            // so move onto the next in the queue
            continue;
          }
        }
      }

      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (typeof child.offsetTop !== 'undefined' &&
            typeof child.offsetHeight !== 'undefined') {
          // offsetHeight already accounts for border-bottom, padding-bottom.
          var bottom = child.offsetTop + child.offsetHeight +
              parseIntFromElemPxAttribute(child, 'margin-bottom');
          result = Math.max(result, bottom);
        }
        queue.push(child);
      }
    }

    // Add border, padding and margin of the containing body.
    return result +
        parseIntFromElemPxAttribute(document.body, 'border-bottom') +
        parseIntFromElemPxAttribute(document.body, 'margin-bottom') +
        parseIntFromElemPxAttribute(document.body, 'padding-bottom');
  }
}());
