var ESN = {};

DOM.addEventListener(window, "load", function (evt) {
  ESN.initCheckAllBtns();
  ESN.initEventCheckBtns();
});

// When page loads, set up "check all" checkboxes
ESN.initCheckAllBtns = function () {
  var ntids  = $("ntypeids");
  var catids = $("catids");

  if (!ntids || !catids)
    return;

  ntidList  = ntids.value;
  catidList = catids.value;

  if (!ntidList || !catidList)
    return;

  ntids  = ntidList.split(",");
  catids = catidList.split(",");

  catids.forEach( function (catid) {
    ntids.forEach( function (ntypeid) {
      var className = "SubscribeCheckbox-" + catid + "-" + ntypeid;

      var cab = new CheckallButton();
      cab.init({
        "class": className,
          "button": $("CheckAll-" + catid + "-" + ntypeid),
          "parent": $("CategoryRow-" + catid)
          });
    });
  });
}

// set up auto show/hiding of notification methods
ESN.initEventCheckBtns = function () {
  var etids = $("etypeids");
  var ntids = $("ntypeids");
  if (!etids || !ntids)
    return;

  etidList = etids.value;
  ntidList = ntids.value;
  if (!etidList || !ntidList)
    return;

  etids = etidList.split(",");
  ntids = ntidList.split(",");

  ESN.ntids = ntids;

  etids.forEach( function (etypeid) {
    var check = $("subscribe" + etypeid);
    if (!check)
      return;

    check.etypeid = etypeid;
    DOM.addEventListener(check, "click", ESN.eventChecked.bindEventListener());
  });
}

ESN.eventChecked = function (evt) {
  var target = evt.target;
  if (!target)
    return;

  var etypeid = evt.target.etypeid;
  var ntids = ESN.ntids;
  if (!ntids || !etypeid)
    return;

  // hide/unhide notification methods for this row
  ntids.forEach( function (ntypeid) {
    var row = $("NotificationOptions-" + etypeid + "-" + ntypeid);
    if (!row)
      return;

    row.style.visibility = target.checked ? "visible" : "hidden";
  });
}
