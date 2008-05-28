function lastfm_current ( username ) {
    var req = { method : "POST", 
        data : HTTPReq.formEncoded({ "username" : username }),
        url : "/tools/endpoints/lastfm_current_track.bml",
        onData : import_handle,
        onError : import_error
    };
    HTTPReq.getJSON(req);
};

var jobstatus;
var timer;

function import_handle(info) {
    if (info.error) {
        document.getElementById('prop_current_music').value = info.error;
        return import_error(info.error);
    }

    document.getElementById('prop_current_music').value = "Running, please wait...";
    jobstatus = new JobStatus(info.handle, got_track);
    timer = window.setInterval(jobstatus.updateStatus.bind(jobstatus), 1500);
    done = 0; // If data already received or not
};

function got_track (info) {
    if (info.running) {
    } else {
        window.clearInterval(timer);

        if (info.status == "success") {
            if (done)
                return;

            done = 1;
                    
            eval('var result = ' + info.result);
            if (result.error != '') {
                document.getElementById('prop_current_music').value = '';
                LiveJournal.ajaxError(result.error);
            } else {
                document.getElementById('prop_current_music').value = result.data;
            }
        } else {
            document.getElementById('prop_current_music').value = '';
            LiveJournal.ajaxError('Failed to receive track from Last.fm');
        }
    }
}

function import_error(msg) {
    LiveJournal.ajaxError(msg);
}

