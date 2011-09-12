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

gadgets.util = gadgets.util || {};

/**
 * Attach an event listener to given DOM element (Not a gadget standard)
 *
 * @param {Object} elem  DOM element on which to attach event.
 * @param {string} eventName  Event type to listen for.
 * @param {function()} callback  Invoked when specified event occurs.
 * @param {boolean} useCapture  If true, initiates capture.
 */
gadgets.util.attachBrowserEvent = function(elem, eventName, callback, useCapture) {
  if (typeof elem.addEventListener != 'undefined') {
    elem.addEventListener(eventName, callback, useCapture);
  } else if (typeof elem.attachEvent != 'undefined') {
    elem.attachEvent('on' + eventName, callback);
  } else {
    gadgets.warn('cannot attachBrowserEvent: ' + eventName);
  }
};

/**
 * Remove event listener. (Shindig internal implementation only)
 *
 * @param {Object} elem  DOM element from which to remove event.
 * @param {string} eventName  Event type to remove.
 * @param {function()} callback  Listener to remove.
 * @param {boolean} useCapture  Specifies whether listener being removed was added with
 *                              capture enabled.
 */
gadgets.util.removeBrowserEvent = function(elem, eventName, callback, useCapture) {
  if (elem.removeEventListener) {
    elem.removeEventListener(eventName, callback, useCapture);
  } else if (elem.detachEvent) {
    elem.detachEvent('on' + eventName, callback);
  } else {
    gadgets.warn('cannot removeBrowserEvent: ' + eventName);
  }
};

