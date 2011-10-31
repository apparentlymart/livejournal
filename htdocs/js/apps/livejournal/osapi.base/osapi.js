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
 * Called by the transports for each service method that they expose
 * @param {string} method  The method to expose e.g. "people.get".
 * @param {Object.<string,Object>} transport The transport used to
 *    execute a call for the method.
 */
osapi._registerMethod = function(method, transport) {
  // Skip registration of local newBatch implementation.
  if (method === 'newBatch') {
    return;
  }

  // Lookup last method value.
  var parts = method.split('.');
  var last = osapi;
  for (var i = 0; i < parts.length - 1; i++) {
    last[parts[i]] = last[parts[i]] || {};
    last = last[parts[i]];
  }
  var basename = parts[parts.length - 1], old;

  // registered methods are now 'last one in wins'.  See tamings__ below.
  if (last[basename]) {
    old = last[basename];
  }

  last[basename] = function(rpc, callback, st) {
    // TODO: This shouldn't really be necessary. The spec should be clear
    // enough about defaults that we dont have to populate this.
    rpc = rpc || {};
    rpc['userId'] = rpc['userId'] || '@viewer';
    rpc['groupId'] = rpc['groupId'] || '@self';
    if (osapi.container) {
        //ugly hack to allow to call JSON-RPC from the container side
        var boundCall = new osapi._BoundCall(method, transport, rpc, st);
        boundCall.execute(callback);
    } else {
        var boundCall = new osapi._BoundCall(method, transport, rpc);
        return boundCall;
    }
  };

  if (typeof tamings___ !== 'undefined') {
    var newTaming = function() {
      caja___.markTameAsFunction(last[basename], method);
    };

    // Remove the old taming if we are replacing it, no sense in growing the array
    // needlessly. This function (_registerMethod) gets called a lot.
    if (old && old.__taming_index) {
      last[basename].__taming_index = old.__taming_index;
      tamings___[old.__taming_index] = newTaming;
    }
    else {
      last[basename].__taming_index = tamings___.length;
      tamings___.push(newTaming);
    }
  }
};

// This was formerly an anonymous ad-hoc object, but that triggers a caja
// bug: http://code.google.com/p/google-caja/issues/detail?id=1355
// Workaround is to make it a class.
osapi._BoundCall = function(method, transport, rpc, st) {
  this['method'] = method;
  this['transport'] = transport;
  this['rpc'] = rpc;
  this['token'] = st;
};

osapi._BoundCall.prototype.execute = function(callback) {
  var cajaReady = (typeof caja___ !== 'undefined'
                   && caja___.getUseless
                   && caja___.getUseless());
  var that = cajaReady ? caja___.getUseless() : this;
  var feralCallback = cajaReady ? caja___.untame(callback) : callback;
  var batch = osapi.newBatch(this.token);
  batch.add(this.method, this);
  batch.execute(function(batchResult) {
    if (batchResult.error) {
      feralCallback.call(that, batchResult.error);
    } else {
      feralCallback.call(that, batchResult[that.method]);
    }
  });
};

