UserpicSelect = new Class (LJ_IPPU, {
  init: function () {
    UserpicSelect.superClass.init.apply(this, ["Choose Userpic"]);
    this.setDimensions("60%", "80%");
    this.selectedkw = null;

    var template = new Template( UserpicSelect.top );
    var templates = { body: template };
    this.setContent(template.exec( new Template.Context( {}, templates ) ));
  },

  show: function() {
    UserpicSelect.superClass.show.apply(this, []);
    this.setStatus("Loading...");
    this.loadPics();
  },

  setStatus: function(status) {
    this.setField({'status': status});
  },

  setField: function(vars) {
    var template = new Template( UserpicSelect.dynamic );
    var userpics_template = new Template( UserpicSelect.userpics );

    var templates = {
      body: template,
      userpics: userpics_template
    };

    if (!vars.pics)
      vars.pics = {};

    if (!vars.status)
      vars.status = "";

    $("ups_dynamic").innerHTML = (template.exec( new Template.Context( vars, templates ) ));

    if (vars.pics.kws) {
      for (var i=0; i<vars.pics.kws.length; i++) {
        var pickw = vars.pics.kws[i];
        var pic = vars.pics.pics[pickw];

        // add onclick handlers for each of the images
        var cell = $("ups_upicimg" + pickw);
        if (cell) {
          cell.kw = pickw;
          this.addClickHandler(cell);
        }
      }
    }
  },

  kwmenuChange: function(evt) {
    this.selectKeyword($("ups_kwmenu").value);
  },

  selectKeyword: function(kw) {
    if (this.selectedkw)
      DOM.removeClassName($("ups_upicimg" + this.selectedkw), "ups_selected");

    var kwimg =  $("ups_upicimg" + kw);
    if (!kwimg)
      return;

    DOM.addClassName(kwimg, "ups_selected");

    this.selectedkw = kw;
  },

  addClickHandler: function(cell) {
    DOM.addEventListener(cell, "click", this.cellClick.bindEventListener(this));
  },

  cellClick: function(evt) {
    evt = Event.prep(evt);
    Event.stop(evt);

    var target = evt.target;
    if (!target)
      return;

    var kw = target.kw;
    if (!defined(kw))
      return;

    this.selectKeyword(kw);
  },

  filterPics: function() {
    var filter = $("ups_search").value.toLocaleUpperCase();
    var pics = this.pics;

    if (!filter) {
      this.setPics(pics);
      return;
    }

    var newpics = {};
    newpics.kws = [];
    newpics.pics = {};

    for (var i=0; i<pics.kws.length; i++) {
      var pickw = pics.kws[i];

      var piccomment;

      if (pics.pics[pickw].comment)
        piccomment = pics.pics[pickw].comment.toLocaleUpperCase();

      if(pickw.toLocaleUpperCase().indexOf(filter) != -1 || (piccomment && piccomment.indexOf(filter) != -1)) {
        newpics.pics[pickw] = pics.pics[pickw];
        newpics.kws.push(pickw);
      }
    }
    this.setPics(newpics);
  },

  setDropdown: function(pics) {
    var menu = $("ups_kwmenu");

    for (var i=0; i<menu.length; i++)
      menu.remove(i);

    for (var i=0; i<pics.kws.length; i++) {
      var pickw = pics.kws[i];

      // add to dropdown
      var picopt = document.createElement("option");
      picopt.text = pickw;
      picopt.value = pickw;
      menu.add(picopt, null);
    }
  },

  picsReceived: function(picinfo) {
    this.setStatus();
    this.pics = picinfo;
    this.setPics(picinfo);
    $("ups_search").focus();
    this.hourglass.hide();

    var kws = [];
    var comments = [];

    var searchbox = $("ups_search");

    var compdata = new InputCompleteData(kws.concat(comments));
    //var whut = new InputComplete(searchbox, compdata);

    DOM.addEventListener(searchbox, "keydown",  this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "keyup",    this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "blur",     this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "focus",    this.filterPics.bind(this));

    try {
      searchbox.focus();
    } catch(e) {}

    DOM.addEventListener($("ups_kwmenu"), "change", this.kwmenuChange.bindEventListener(this));
  },

  setPics: function(pics) {
    this.setField({'pics': pics});
    this.setDropdown(pics);
  },

  handleError: function(err) {
    alert("Error: " + err);
    this.hourglass.hide();
  },

  loadPics: function() {
    this.hourglass = new Hourglass($("ups_userpics"));
    var reqOpts = {};
    reqOpts.url = "/tools/endpoints/getuserpics.bml";
    reqOpts.onData = this.picsReceived.bind(this);
    reqOpts.onError = this.handleError.bind(this);
    HTTPReq.getJSON(reqOpts);
  }
});

UserpicSelect.top = "\
      <div class='ups_search'>\
       <span class='ups_searchbox'>\
         Search: <input type='text' id='ups_search'>\
         Select: <select id='ups_kwmenu'><option value=''></option></select>\
       </span>\
      </div>\
      <div id='ups_dynamic'></div>";

UserpicSelect.dynamic = "\
       [# if (status) { #] <div class='ups_status'>[#| status #]</div> [# } #]\
         <div class='ups_userpics' id='ups_userpics'>\
           [#= context.include( 'userpics' ) #]\
           &nbsp;\
         </div>\
      <div class='ups_closebuttonarea'>\
       <input type='button' id='ups_closebutton' value='Select' />\
      </div>";

UserpicSelect.userpics = "\
[# if(pics && pics.kws) { \
#] <div class='ups_table'> [# \
   var rownum = 0; \
   for (var i=0; i<pics.kws.length; i++) { \
     var pickw = pics.kws[i]; \
     var pic = pics.pics[pickw]; \
     if (i%2 == 0) { #] \
     <div class='ups_row ups_row[#= rownum++ % 2 + 1 #]'> [# } #] \
\
       <span class='ups_cell' style='width: [#= pic.width/2 #]px;' > \
         <img src='[#= pic.url #]' width='[#= finiteInt(pic.width/2) #]' \
            height='[#= finiteInt(pic.height/2) #]' id='ups_upicimg[#= pickw #]' class='ups_upic' /> \
       </span> \
       <span class='ups_cell'> \
         <b>[#| pickw #]</b> \
         [# if(pic.comment) { #]<br/>[#= pic.comment #][# } #] \
       </span> \
\
     [# if (i%2 == 1) { #] </div> [# } \
    } #] \
  </div> \
  [# } #] \
";
