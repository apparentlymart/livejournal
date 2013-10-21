//= require js/ljwidget_ippu.js

LJWidgetIPPU_AddAlias = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::AddAlias";
    this.width = opts.width; // Use for resizing later
    this.height = opts.height; // Use for resizing later
    this.alias = opts.alias;
    LJWidgetIPPU_AddAlias.superClass.init.apply(this, arguments);
  },

  addvgifttocart: function (evt, form) {
    var alias = form["Widget[IPPU_AddAlias]_alias"].value + "";
    var foruser = form["Widget[IPPU_AddAlias]_foruser"].value + "";

    this.doPost({
        alias:          alias,
        foruser:            foruser
    });

    Event.stop(evt);
  },

  onData: function (data) {
    var success;
    if (data.res && data.res.success) success = data.res.success;
    if (success) {

      LJ_IPPU.showNote("Virtual gift added to your cart.");
      this.ippu.hide();
      /*
      var userLJ=data.res.link;
      var searchUser1=DOM.getElementsByAttributeAndValue(document,'href',userLJ+"/");
      var searchUser2=DOM.getElementsByAttributeAndValue(document,'href',userLJ);
      var searchProfile=searchUser1.concat(searchUser2); 
      var supSign;
      for(var i=0;i<searchProfile.length;i++){
	if(DOM.hasClassName(searchProfile[i].parentNode,'ljuser')){
		if(!DOM.hasClassName(searchProfile[i].parentNode,'with-alias')){
			DOM.addClassName(searchProfile[i].parentNode,'with-alias')
			supSign=document.createElement('sup');
			supSign.innerHTML='&#x2714;';
			searchProfile[i].appendChild(supSign);
		}
		else{
			if(data.res.alias==""){
				DOM.removeClassName(searchProfile[i].parentNode,'with-alias')
				supSign=searchProfile[i].getElementsByTagName('sup')[0];
				searchProfile[i].removeChild(supSign);
			}
		
		}
		searchProfile[i].setAttribute('title',data.res.alias);
		//Adding alias to name only in profile
		if(DOM.hasClassName(searchProfile[i].parentNode.parentNode,'username')){
			console.log(searchProfile[i].parentNode.parentNode.nextSibling);
			if(DOM.hasClassName(searchProfile[i].parentNodentNode.nextSibling,'alias-value')){
				console.log('x');
				searchProfile[i].parentNode.nextSibling.innerHTML='('+data.res.alias+')';
			}
		}
	}
	
      }
      */
    }
  },

  onError: function (msg) {
    LJ_IPPU.showErrorNote("Error: " + msg);
  },

  onRefresh: function () {
    var self = this;
//    var cancelBtn = $('addvgift_cancel');
//    if (cancelBtn) DOM.addEventListener(cancelBtn, 'click', self.cancel.bindEventListener(this));

    var form = $("addalias_form");
    DOM.addEventListener(form, "submit", function(evt) { self.addvgifttocart(evt, form) });

//    $('Widget[IPPU_AddAlias]_whom').value = this.whom;
//    AutoCompleteFriends($('Widget[IPPU_AddAlias]_whom'));
  },

  cancel: function (e) {
    this.close();
  }
});
