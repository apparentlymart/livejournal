/*
 * ExpanderEx object is used in s1 style comment pages and provides
 * ajax functionality to expand comments instead of loading iframe page as it is
 * in old Expander
 * expander object is also used in commentmanage.js
 */
ExpanderEx = function(){
    this.__caller__;    // <a> HTML element from where ExpanderEx was called
    this.url;           // full url of thread to be expanded
    this.id;            // id of the thread
    this.stored_caller;
    this.is_S1;         // bool flag, true == journal is in S1, false == in S2
}
ExpanderEx.Collection={};
ExpanderEx.ReqCache = {};

ExpanderEx.make = function(el,url,id,is_S1){
    var local = (new ExpanderEx).set({__caller__:el,url:url.replace(/#.*$/,''),id:id,is_S1:!!is_S1});
    local.get();
}

ExpanderEx.collapse = function(el,url,id,is_S1){
    var local = (new ExpanderEx).set({__caller__:el,url:url.replace(/#.*$/,''),id:id,is_S1:!!is_S1});
    local.collapseThread();
}

ExpanderEx.prototype.set = function(options){
    for(var opt in options){
        this[opt] = options[opt];
    }
    return this;
}

ExpanderEx.prototype.getCanvas = function(id,context){
    return context.document.getElementById('ljcmt'+id);
}

ExpanderEx.prototype.parseLJ_cmtinfo = function(context,callback){
    var map={}, node, j;
    var LJ = context.LJ_cmtinfo;
    if(!LJ)return false;
    for(j in LJ){
        if(/^\d*$/.test(j) && (node = this.getCanvas(j,context))){
            map[j] = {info:LJ[j],canvas:node};
            if(typeof callback == 'function'){
                callback(j,map[j]);
            }
        }
    }
    return map;
}

ExpanderEx.preloadImg = function(){
    (new Image()).src = Site.imgprefix + '/preloader-s.gif?v=3';
}

ExpanderEx.prototype.addPreloader = function(){
    this.loader = new Image();
    this.loader.src = Site.imgprefix + '/preloader-s.gif?v=3';
    this.loader.className = 'i-exp-preloader';
    this.__caller__.parentNode.appendChild( this.loader );
}

ExpanderEx.prototype.removePreloader = function(){
    if( !this.loader ){
        return;
    }

    if( this.loader.parentNode ){
        this.loader.parentNode.removeChild( this.loader );
    }
    delete this.loader;
};

ExpanderEx.prototype.loadingStateOn = function(){
    // turn on preloader there
    this.addPreloader();
    this.stored_caller = this.__caller__.cloneNode(true);
    this.__caller__.setAttribute('already_clicked','already_clicked');
    this.__caller__.onclick = function(){return false}
    this.__caller__.style.color = '#ccc';
}

ExpanderEx.prototype.loadingStateOff = function(){
    if(this.__caller__){
        // actually, the <a> element is removed from main window by
        // copying comment from ifame, so this code is not executed (?)
        this.__caller__.removeAttribute('already_clicked','already_clicked');
        if(this.__caller__.parentNode) this.__caller__.parentNode.replaceChild(this.stored_caller,this.__caller__);
        //remove preloader if exist
        this.removePreloader();
    }
    var obj = this;
    // When frame is removed immediately, IE raises an error sometimes
}

ExpanderEx.prototype.killFrame = function(){
    document.body.removeChild(this.iframe);
}

ExpanderEx.prototype.isFullComment = function( comment ) {
    return !!Number(comment.info.full);
}

ExpanderEx.prototype.expandThread = function( json ) {
    this.loadingStateOff();

    //we show expand link if comment block has collapsed children
    function isChildCollapsed( idx )
    {
        var state;
        for( var i = idx + 1; i < json.length; ++i ) {
            state = json[ i ].state;
            if( state === "expanded" ) { return false; }
            if( state === "collapsed" ) { return true; }
        }

        return  false;
    }

    var threadId, cell, html;
    for( var i = 0; i < json.length; ++i ) {
        //we skip comment blocks thate were not expanded
        if( json[ i ].state === 'deleted' ) {
            LJ_cmtinfo[ json[ i ].thread ].is_deleted = true;
        }
		if( !( json[ i ].thread in LJ_cmtinfo ) ) {
			continue;
		}
        if( json[ i ].state && json[ i ].state !== "expanded") {
            continue;
        }

        threadId = json[ i ].thread;
        html = ExpanderEx.prepareCommentBlock( jQuery( json[ i ].html ), threadId, isChildCollapsed( i ) );

        var oldHtml = LiveJournal.CommentManager.updateCell( threadId, html );
        if( !( threadId in ExpanderEx.Collection ) ) {
            ExpanderEx.Collection[ threadId ] = oldHtml;
        }
    }

    //duplicate cycle, because we do not know, that external scripts do with node
    for( var i = 0; i < json.length; ++i ) {
        threadId = json[ i ].thread;
        LJ_cmtinfo[ threadId ].parent = this.id;
        if( json[ i ].state && json[ i ].state === "expanded") {
            this.initCommentBlock( jQuery( '#ljcmt' + threadId )[0] , threadId );
        }
    }

    return true;
}

ExpanderEx.prototype.collapseThread = function( id ){
    var threadId = id || this.id;
    this.collapseBlock( threadId );

    var children = LJ_cmtinfo[ threadId ].rc;
    for( var i = 0; i < children.length; ++i )
        this.collapseThread( children[ i ] );
}

ExpanderEx.prototype.collapseBlock =  function( id )
{
	if( id in ExpanderEx.Collection ) {
		LiveJournal.CommentManager.updateCell( id, ExpanderEx.Collection[ id ] );

		this.initCommentBlock( LiveJournal.CommentManager.getCell( id )[0], id, true );
		delete ExpanderEx.Collection[ id ];
	}
}

ExpanderEx.prototype.initCommentBlock = function( el_, id, restoreInitState )
{
    if( !restoreInitState ){
        LJ_cmtinfo[ id ].oldvars = {
            full: LJ_cmtinfo[ id ].full || 0,
            expanded: LJ_cmtinfo[ id ].expanded || 0
        }
        LJ_cmtinfo[ id ].full = 1;
        LJ_cmtinfo[ id ].expanded = 1;
    }
    else {
        LJ_cmtinfo[ id ].full = LJ_cmtinfo[ id ].oldvars.full;
        LJ_cmtinfo[ id ].expanded = LJ_cmtinfo[ id ].oldvars.expanded;
        delete LJ_cmtinfo[ id ].oldvars;
    }
    window.ContextualPopup && ContextualPopup.searchAndAdd(el_);
    //window.setupAjax && setupAjax(el_, true);
    window.ESN && ESN.initTrackBtns(el_);
}


//just for debugging
ExpanderEx.prototype.toString = function(){
    return '__'+this.id+'__';
}


ExpanderEx.prototype.get = function(){
    if(this.__caller__.getAttribute('already_clicked')){
        return false;
    }
    this.loadingStateOn();

    var obj = this;
    //set timeout to allow browser to display image before request
    setTimeout( function(){
        LiveJournal.CommentManager.getThreadJSON( obj.id, function(result) {
            obj.expandThread(result);
            ExpanderEx.ReqCache[ obj.id ] = result;
        }, false, false, true );
    }, 0 );

    return true;
}

//toggle visibility of expand and collapse links, if server returns
//html with both of them ( with every ajax request)
ExpanderEx.prepareCommentBlock = function(html, id, showExpand){
    this.showExpandLink( id, html, showExpand );
    return html;
}

ExpanderEx.showExpandLink = function ( id, block, showExpand ) {
    var expandSel = "#expand_" + id,
        collapseSel = "#collapse_" + id,
        selector, resetSelector;

    if( LJ_cmtinfo[ id ].has_link > 0 ) {
        if( showExpand ) {
            selector = collapseSel;
            resetSelector = expandSel;
        } else {
            selector = expandSel;
            resetSelector = collapseSel;
        }
        block.find( resetSelector ).css( 'display', '' );
    }
    else {
        selector = collapseSel + "," + expandSel;
    }

    block.find( selector )
        .css( 'display', 'none' );
}

ExpanderEx.preloadImg();
