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

// Draft was saved successfully, we update the status line within the callback
// passed to getDraft.
function draftSaved (res) {
}

// Since this is supposed to be a background task, we don't want to present errors
// to the user.  We do however need to have this callback.  In the future we may
// try and do something with errors.
function draftError (err) {
}

// initiates a request to get the current draft. doesn't actually return the data. data is returned to callback.
function getDraft(callback) {
    draftReqOpts.onData = callback;
    HTTPReq.getJSON(draftReqOpts);
}
