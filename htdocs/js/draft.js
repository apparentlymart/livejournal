var draftReqOpts = {
    "url": "/tools/endpoints/draft.bml",
    "onError": draftError
};

function saveDraft (draft) {
    var reqOpts = draftReqOpts;
    reqOpts.method = "POST";
    reqOpts.onData = draftSaved;
    reqOpts.data = HTTPReq.formEncoded({"saveDraft": draft});
    HTTPReq.getJSON(reqOpts);
}

// draft was saved successfully, if you care
function draftSaved (res) {

}

function draftError (err) {
    // error handling? eh
        alert(err);
}

// initiates a request to get the current draft. doesn't actually return the data. data is returned to callback.
function getDraft(callback) {
    draftReqOpts.onData = callback;
    HTTPReq.getJSON(draftReqOpts);
}
