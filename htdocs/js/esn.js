var esnM = new ESNManager();

function initEsn (etypeids) {
  if (!etypeids) return;
  if (!esnM) return;

  esnM.init(etypeids);
}

function showETypeid (etypeid) {
  esnM.show(etypeid);
}

DOM.addEventListener(window, "load", function (evt) {
  var eventMenu = $("etypeid");
  if (!eventMenu) return;

  DOM.addEventListener(eventMenu, "change", menuChanged.bindEventListener());
});

function menuChanged (evt) {
  var eventMenu = $("etypeid");
  if (!eventMenu) return;

  var etypeid = eventMenu.value;
  showETypeid(etypeid);
}
