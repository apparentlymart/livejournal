UserpicSelect = new Class (LJ_IPPU, {
  init: function () {
    UserpicSelect.superClass.init.apply(this, ["Choose Userpic"]);
    this.setDimensions("60%", "80%");
    this.selectedPicid = null;
    this.displayPics = null;
    this.dataLoaded = false;

    this.picSelectedCallback = null;

    var template = new Template( UserpicSelect.top );
    var templates = { body: template };
    this.setContent(template.exec( new Template.Context( {}, templates ) ));
    this.setHiddenCallback(this.hidden.bind(this));
  },

  show: function() {
    UserpicSelect.superClass.show.apply(this, []);

    if (!this.dataLoaded) {
      this.setStatus("Loading...");
      this.loadPics();
      this.dataLoaded = true;
    } else {
      this.redraw();
    }
  },

  // hide the hourglass when window is closed
  hidden: function () {
    if (this.hourglass)
      this.hourglass.hide();
  },

  // set a callback to be called when the "select" button is clicked
  setPicSelectedCallback: function (callback) {
    this.picSelectedCallback = callback;
  },

  // called when the "select" button is clicked
  closeButtonClicked: function (evt) {
    if (this.picSelectedCallback)
      this.picSelectedCallback(this.selectedPicid);

    this.hide();
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
      vars.pics = this.pics || {};

    if (!vars.status)
      vars.status = "";

    $("ups_dynamic").innerHTML = (template.exec( new Template.Context( vars, templates ) ));

    if (!vars.pics.ids)
      return;

    for (var i=0; i<vars.pics.ids.length; i++) {
      var picid = vars.pics.ids[i];
      var pic = vars.pics.pics[picid];

      if (!pic)
        continue;

      // add onclick handlers for each of the images
      var cell = $("ups_upicimg" + picid);
      if (cell) {
        cell.picid = picid;
        this.addClickHandler(cell);
      }
    }

    // we redrew the window so reselect the current selection, if any
    if (this.selectedPicid)
      this.selectPic(this.selectedPicid);
  },

  kwmenuChange: function(evt) {
    this.selectPic($("ups_kwmenu").value);
  },

  selectPic: function(picid) {
    if (this.selectedPicid)
      DOM.removeClassName($("ups_upicimg" + this.selectedPicid), "ups_selected");

    // find the current picture
    var picimg =  $("ups_upicimg" + picid);

    if (!picimg)
      return;

    // hilight the userpic
    DOM.addClassName(picimg, "ups_selected");

    this.selectedPicid = picid;

    // enable the select button
    $("ups_closebutton").disabled = false;

    // select the current selectedPicid in the dropdown
    this.setDropdown();
  },

  addClickHandler: function(cell) {
    DOM.addEventListener(cell, "click", this.cellClick.bindEventListener(this));
  },

  cellClick: function(evt) {
    Event.stop(evt);

    var target = evt.target;
    if (!target)
      return;

    var picid = target.picid;
    if (!defined(picid))
      return;

    this.selectPic(picid);
  },

  // filter by keyword/comment
  filterPics: function(evt) {
    var searchbox = $("ups_search");

    if (!searchbox)
      return;

    var filter = searchbox.value.toLocaleUpperCase();
    var pics = this.pics;

    if (!filter) {
      this.setPics(pics);
      return;
    }

    // if there is a filter and there is selected text in the field assume that it's
    // inputcomplete text and ignore the rest of the selection.
    if (searchbox.selectionStart && searchbox.selectionStart > 0)
      filter = searchbox.value.substr(0, searchbox.selectionStart).toLocaleUpperCase();

    var newpics = {
      "pics": [],
      "ids": []
    };

    for (var i=0; i<pics.ids.length; i++) {
      var picid = pics.ids[i];
      var pic = pics.pics[picid];

      if (!pic)
        continue;

      var piccomment;

      if (pic.comment)
        piccomment = pic.comment.toLocaleUpperCase();

      for (var j=0; j < pic.keywords.length; j++) {
        var kw = pic.keywords[j];

        if(kw.toLocaleUpperCase().indexOf(filter) != -1 || // matches a keyword
           (piccomment && piccomment.indexOf(filter) != -1) || // matches comment
           (pic.keywords.join(", ").toLocaleUpperCase().indexOf(filter) != -1)) { // matches comma-seperated list of keywords

          newpics.pics[picid] = pic;
          newpics.ids.push(picid);
          break;
        }
      }
    }

    if (this.pics != newpics)
      this.setPics(newpics);

    // if we've filtered down to one pic and we don't currently have a selected pic, select it
    if (newpics.ids.length == 1 && !this.selectedPicid)
      this.selectPic(newpics.ids[0]);
  },

  setDropdown: function(pics) {
    var menu = $("ups_kwmenu");

    for (var i=0; i < menu.length; i++)
      menu.remove(i);

    menu.length = 0;

    if (!pics)
      pics = this.pics;

    if (!pics || !pics.ids)
      return;

    for (var i=0; i < pics.ids.length; i++) {
      var picid = pics.ids[i];
      var pic = pics.pics[picid];

      if (!pic)
        continue;

      // add to dropdown
      var picopt = document.createElement("option");
      picopt.text = pic.keywords.join(", ");
      picopt.value = picid;

      picopt.selected = this.selectedPicid ? this.selectedPicid == picid : false;

      menu.add(picopt, null);
    }
  },

  picsReceived: function(picinfo) {
    if (picinfo && picinfo.alert) { // got an error
      this.handleError(picinfo.alert);
      return;
    }

    if (!picinfo || !picinfo.ids || !picinfo.pics || !picinfo.ids.length)
      return;

    // force convert integers to strings
    for (var i=0; i < picinfo.ids.length; i++) {
      var picid = picinfo.ids[i];

      var pic = picinfo.pics[picid];

      if (!pic)
        continue;

      if (pic.comment)
        pic.comment += "";

      for (var j=0; j < pic.keywords.length; j++)
        pic.keywords[j] += "";
    }

    this.pics = picinfo;

    this.setPics(picinfo);
    this.redraw();

    if (this.hourglass)
      this.hourglass.hide();
  },

  redraw: function () {
    this.setStatus();

    if (!this.pics)
      return;

    this.setPics(this.pics);

    if (this.hourglass)
      this.hourglass.hide();

    var keywords = [], comments = [];
    for (var i=0; i < this.pics.ids.length; i++) {
      var picid = this.pics.ids[i];
      var pic = this.pics.pics[picid];

      for (var j=0; j < pic.keywords.length; j++)
        keywords.push(pic.keywords[j]);

      comments.push(pic.comment);
    }

    var searchbox = $("ups_search");
    var compdata = new InputCompleteData(keywords.concat(comments));
    var whut = new InputComplete(searchbox, compdata);

    DOM.addEventListener(searchbox, "keydown",  this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "keyup",    this.filterPics.bind(this));
    DOM.addEventListener(searchbox, "focus",    this.filterPics.bind(this));

    try {
      searchbox.focus();
    } catch(e) {}

    DOM.addEventListener($("ups_kwmenu"), "change", this.kwmenuChange.bindEventListener(this));

    DOM.addEventListener($("ups_closebutton"), "click", this.closeButtonClicked.bindEventListener(this));

  },

  setPics: function(pics) {
    if (this.displayPics == pics)
      return;

    this.displayPics = pics;

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

// Templates
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
       <input type='button' id='ups_closebutton' value='Select' disabled='true' />\
      </div>";

UserpicSelect.userpics = "\
[# if(pics && pics.ids) { #] \
     <div class='ups_table'> [# \
       var rownum = 0; \
       for (var i=0; i<pics.ids.length; i++) { \
          var picid = pics.ids[i]; \
          var pic = pics.pics[picid]; \
\
          if (!pic) \
            continue; \
\
          var pickws = pic.keywords; \
          if (i%2 == 0) { #] \
            <div class='ups_row ups_row[#= rownum++ % 2 + 1 #]'> [# } #] \
\
            <span class='ups_cell' style='width: [#= pic.width/2 #]px;' > \
              <img src='[#= pic.url #]' width='[#= finiteInt(pic.width/2) #]' \
                 height='[#= finiteInt(pic.height/2) #]' id='ups_upicimg[#= picid #]' class='ups_upic' /> \
            </span> \
            <span class='ups_cell'> \
              <b>[#| pickws.join(', ') #]</b> \
             [# if(pic.comment) { #]<br/>[#= pic.comment #][# } #] \
            </span> \
\
            [# if (i%2 == 1 || i == pics.ids.length - 1) { #] </div> [# } \
        } #] \
     </div> \
  [# } #] \
";
