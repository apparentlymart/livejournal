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


/**
 * Creates a closure that is suitable for passing as a callback.
 * Any number of arguments
 * may be passed to the callback;
 * they will be received in the order they are passed in.
 *
 * @param {Object} scope The execution scope; may be null if there is no
 *     need to associate a specific instance of an object with this
 *     callback.
 * @param {function(Object,Object)} callback The callback to invoke when
 *     this is run; any arguments passed in will be passed after your initial
 *     arguments.
 * @param {Object} var_args Initial arguments to be passed to the callback.
 * @return {function()} a callback function.
 */
gadgets.util.makeClosure = function(scope, callback, var_args) {
  // arguments isn't a real array, so we copy it into one.
  var baseArgs = [];
  for (var i = 2, j = arguments.length; i < j; ++i) {
    baseArgs.push(arguments[i]);
  }
  return function() {
    // append new arguments.
    var tmpArgs = baseArgs.slice();
    for (var i = 0, j = arguments.length; i < j; ++i) {
      tmpArgs.push(arguments[i]);
    }
    return callback.apply(scope, tmpArgs);
  };
};


/**
 * Utility function for generating an "enum" from an array.
 *
 * @param {Array.<string>} values The values to generate.
 * @return {Object.<string,string>} An object with member fields to handle
 *   the enum.
 */
gadgets.util.makeEnum = function(values) {
  var i, v, obj = {};
  for (i = 0; (v = values[i]); ++i) {
    obj[v] = v;
  }
  return obj;
};

