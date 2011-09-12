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

  /**
   * @enum {boolean}
   * @const
   * @private
   * Maps code points to the value to replace them with.
   * If the value is "false", the character is removed entirely, otherwise
   * it will be replaced with an html entity.
   */
  var escapeCodePoints = {
    // nul; most browsers truncate because they use c strings under the covers.
    0 : false,
    // new line
    10 : true,
    // carriage return
    13 : true,
    // double quote
    34 : true,
    // single quote
    39 : true,
    // less than
    60 : true,
    // greater than
    62 : true,
    // backslash
    92 : true,
    // line separator
    8232 : true,
    // paragraph separator
    8233 : true,
    // fullwidth quotation mark
    65282 : true,
    // fullwidth apostrophe
    65287 : true,
    // fullwidth less-than sign
    65308 : true,
    // fullwidth greater-than sign
    65310 : true,
    // fullwidth reverse solidus
    65340 : true
  };

  /**
   * Regular expression callback that returns strings from unicode code points.
   *
   * @param {Array} match Ignored.
   * @param {number} value The codepoint value to convert.
   * @return {string} The character corresponding to value.
   */
  function unescapeEntity(match, value) {
    // TODO: b0rked for UTF-16 and can easily be convinced to generate
    // truncating NULs or completely invalid non-Unicode characters. Here's a
    // fixed version (it handles entities for valid codepoints from U+0001 ...
    // U+10FFFD, except for the non-character codepoints U+...FFFE and
    // U+...FFFF; isolated UTF-16 surrogate pairs are supported for
    // compatibility with previous versions of escapeString, 0 generates the
    // empty string rather than a possibly-truncating '\0', and all other inputs
    // generate U+FFFD (the replacement character, standard practice for
    // non-signalling Unicode codecs like this one)
    //     return (
    //         (value > 0) &&
    //         (value <= 0x10fffd) &&
    //         ((value & 0xffff) < 0xfffe)) ?
    //       ((value <= 0xffff) ?
    //         String.fromCharCode(value) :
    //         String.fromCharCode(
    //           ((value - 0x10000) >> 10) | 0xd800,
    //           ((value - 0x10000) & 0x3ff) | 0xdc00)) :
    //       ((value === 0) ? '' : '\ufffd');
    return String.fromCharCode(value);
  }

  /**
   * Escapes the input using html entities to make it safer.
   *
   * If the input is a string, uses gadgets.util.escapeString.
   * If it is an array, calls escape on each of the array elements
   * if it is an object, will only escape all the mapped keys and values if
   * the opt_escapeObjects flag is set. This operation involves creating an
   * entirely new object so only set the flag when the input is a simple
   * string to string map.
   * Otherwise, does not attempt to modify the input.
   *
   * @param {Object} input The object to escape.
   * @param {boolean=} opt_escapeObjects Whether to escape objects.
   * @return {Object} The escaped object.
   * @private Only to be used by the container, not gadgets.
   */
  gadgets.util.escape = function(input, opt_escapeObjects) {
    if (!input) {
      return input;
    } else if (typeof input === 'string') {
      return gadgets.util.escapeString(input);
    } else if (typeof input === 'array') {
      for (var i = 0, j = input.length; i < j; ++i) {
        input[i] = gadgets.util.escape(input[i]);
      }
    } else if (typeof input === 'object' && opt_escapeObjects) {
      var newObject = {};
      for (var field in input) {
        if (input.hasOwnProperty(field)) {
          newObject[gadgets.util.escapeString(field)] =
              gadgets.util.escape(input[field], true);
        }
      }
      return newObject;
    }
    return input;
  };

  /**
   * Escapes the input using html entities to make it safer.
   *
   * Currently not in the spec -- future proposals may change
   * how this is handled.
   *
   * @param {string} str The string to escape.
   * @return {string} The escaped string.
   */
  gadgets.util.escapeString = function(str) {
    if (!str) return str;
    var out = [], ch, shouldEscape;
    for (var i = 0, j = str.length; i < j; ++i) {
      ch = str.charCodeAt(i);
      shouldEscape = escapeCodePoints[ch];
      if (shouldEscape === true) {
        out.push('&#', ch, ';');
      } else if (shouldEscape !== false) {
        // undefined or null are OK.
        out.push(str.charAt(i));
      }
    }
    return out.join('');
  };

  /**
   * Reverses escapeString
   *
   * @param {string} str The string to unescape.
   * @return {string}
   */
  gadgets.util.unescapeString = function(str) {
    if (!str) return str;
    return str.replace(/&#([0-9]+);/g, unescapeEntity);
  };

})();
