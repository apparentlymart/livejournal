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
 * @fileoverview This represents the container for the current window or create
 * the container if none already exists.
 */

/** @TODO: most of functionality was cut from this container, because it's duplicated
 * in the shindig.container object. In order to unify all the code we should implement
 * GadgetSite and GadgetHolder classes and migrate all the functionality to them from
 * LJGadget, LJContainer, LJIframeService.
 */


/**
 * @param {Object=} opt_config Configuration JSON.
 * @constructor
 */
osapi.container.Container = function(opt_config) {
  var config = this.config_ = opt_config || {};

  /**
   * @type {osapi.container.Service}
   * @private
   */
  this.service_ = new osapi.container.Service(config);

  this.initializeMixins_();

  this.onConstructed(config);
};


/**
 * Callback that occurs after instantiation/construction of this. Override to
 * provide your specific functionalities.
 * @param {Object=} opt_config Configuration JSON.
 */
osapi.container.Container.prototype.onConstructed = function(opt_config) {};


/**
 * Adds a new namespace to the Container object.  The namespace
 * will contain the result of calling the function passed in.
 *
 * @param {string} namespace the namespace to add.
 * @param {function} func to call when creating the namespace.
 */
osapi.container.Container.addMixin = function(namespace, func) {
   osapi.container.Container.prototype.mixins_[namespace] = func;
};


// -----------------------------------------------------------------------------
// Private variables and methods.
// -----------------------------------------------------------------------------


/**
 * Adds the ability for features to extend the container with
 * their own functionality that may be specific to that feature.
 * @type {Object<string,function>}
 * @private
 */
osapi.container.Container.prototype.mixins_ = {};


/**
 * Called from the constructor to add any namespace extensions.
 * @private
 */
osapi.container.Container.prototype.initializeMixins_ = function() {
  for (var i in this.mixins_) {
    this[i] = new this.mixins_[i](this);
  }
};
