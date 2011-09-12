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
 * @fileoverview
 * The global object gadgets.json contains two methods.
 *
 * gadgets.json.stringify(value) takes a JavaScript value and produces a JSON
 * text. The value must not be cyclical.
 *
 * gadgets.json.parse(text) takes a JSON text and produces a JavaScript value.
 * It will return false if there is an error.
 */

/**
 * @static
 * @class Provides operations for translating objects to and from JSON.
 * @name gadgets.json
 */

/**
 * Just wrap native JSON calls when available.
 */
if (window.JSON && window.JSON.parse && window.JSON.stringify) {
  // HTML5 implementation, or already defined.
  // Not a direct alias as the opensocial specification disagrees with the HTML5 JSON spec.
  // JSON says to throw on parse errors and to support filtering functions. OS does not.
  gadgets.json = (function() {
    var endsWith___ = /___$/;

    function getOrigValue(key, value) {
      var origValue = this[key];
      return origValue;
    }

    return {
      /* documented below */
      parse: function(str) {
        try {
          return window.JSON.parse(str);
        } catch (e) {
          return false;
        }
      },
      /* documented below */
      stringify: function(obj) {
        var orig = window.JSON.stringify;
        function patchedStringify(val) {
          return orig.call(this, val, getOrigValue);
        }
        var stringifyFn = (Array.prototype.toJSON && orig([{x:1}]) === "\"[{\\\"x\\\": 1}]\"") ?
            patchedStringify : orig;
        try {
          return stringifyFn(obj, function(k,v) {
            return !endsWith___.test(k) ? v : void 0;
          });
        } catch (e) {
          return null;
        }
      }
    };
  })();
}
