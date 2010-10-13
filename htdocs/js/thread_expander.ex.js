ExpanderEx = function(){
    this.__caller__;    // <a> HTML element from where ExpanderEx was called
    this.url;           // full url of thread to be expanded
    this.id;            // id of the thread
    this.stored_caller;
    this.is_S1;         // bool flag, true == journal is in S1, false == in S2
}
ExpanderEx.Collection={};
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

ExpanderEx.prototype.loadingStateOn = function(){
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
    }
    var obj = this;
    // When frame is removed immediately, IE raises an error sometimes
}

ExpanderEx.prototype.killFrame = function(){
    document.body.removeChild(this.iframe);
}

ExpanderEx.prototype.isFullComment = function(comment){
    return !!Number(comment.info.full);
}

ExpanderEx.prototype.expandThread = function(json){
    this.loadingStateOff();
    for( var i = 0; i < json.length; ++i ) {
        if( json[ i ].thread in ExpanderEx.Collection )
            continue; //this comment is already expanded
        ExpanderEx.Collection[ json[ i ].thread ] = jQuery( '#ljcmtxt' + json[ i ].thread ).html();
        jQuery( '#ljcmtxt' + json[ i ].thread )
            .html( ExpanderEx.prepareCommentBlock( json[ i ].html, json[ i ].thread, false ) );

        this.initCommentBlock( jQuery( '#ljcmt' + json[ i ].thread )[0], json[ i ].thread );
        LJ_cmtinfo[ json[ i ].thread ].parent = this.id;
    }

    return true;
}

ExpanderEx.prototype.collapseThread = function( id ){
    var threadId = id || this.id;
    this.collapseBlock( threadId );

    var children = LJ_cmtinfo[ threadId ].rc;
    for( var i = 0; i < children.length; ++i )
        this.collapseThread( children[ i ] );

    //do not call the code, because we do not know folding logic in all cases
    //this.updateParentState();
}

ExpanderEx.prototype.updateParentState = function()
{
    //if all children were collapsed manually, then we have to change parent
    //comment state to collapsed
    var parentId = LJ_cmtinfo[ this.id ].parent;
    if(!parentId)
        return;

    var allCollapsed = true,
        children = LJ_cmtinfo[ parentId ].rc;
    for( var i = 0; i < children.length; ++i )
        if( LJ_cmtinfo[ children[ i ] ].expanded == 1 ){
            allCollapsed = false;
            break;
        }

    allCollapsed && this.collapseBlock( parentId );
}

ExpanderEx.prototype.collapseBlock =  function( id )
{
    var expander = this;
    function updateBlock(id, html)
    {
        var el_ =jQuery( '#ljcmtxt' + id )
            .html( html )[0];
        expander.initCommentBlock( el_, id, true );
    }

    if( id in ExpanderEx.Collection ){
        updateBlock( id, ExpanderEx.Collection[ id ] );
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
    window.setupAjax && setupAjax(el_, true);
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
    getThreadJSON( this.id, function(result) {
        obj.expandThread(result);
    }, false, false, true );

    return true;
}

ExpanderEx.prepareCommentBlock = function(html, id, showExpand){
    var block = jQuery("<div>" + html + "</div>"),
        selector = '';

    if( LJ_cmtinfo[ id ].has_link > 0 )
        selector = '#' + ((showExpand ? 'collapse_' : 'expand_' ) + id);
    else
        selector = '#collapse_' + id + ', #expand_'  + id

    block.find(selector)
        .css('display', 'none');

    return block.html();
}
