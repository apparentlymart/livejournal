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
 * @class Provides general-purpose utility functions for onload.
 */
gadgets.util = gadgets.util || {};

(function() {

  var onLoadHandlers = [];

  /**
   * Registers an onload handler.
   * @param {function()} callback The handler to run.
   */
  gadgets.util.registerOnLoadHandler = function(callback) {
    onLoadHandlers.push(callback);
  };

  /**
   * Runs all functions registered via registerOnLoadHandler.
   * @private Only to be used by the container, not gadgets.
   */
  gadgets.util.runOnLoadHandlers = function() {
    for (var i = 0, j = onLoadHandlers.length; i < j; ++i) {
      onLoadHandlers[i]();
    }
  };

})();

