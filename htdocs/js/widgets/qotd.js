var QotD = new Object();

QotD.init = function (cnt) {
    QotD.skip = 0;

    // If the buttons aren't found in the DOM, try again 1 second later
    // Do this a maximum of 5 times before failing
    if ($('prev_questions') && $('next_questions')) {
        $('prev_questions').style.display = "inline";
        $('next_questions').style.display = "inline";
        DOM.addEventListener($('prev_questions'), "click", QotD.prevQuestions);
        DOM.addEventListener($('next_questions'), "click", QotD.nextQuestions);
    } else {
        if (cnt > 5) {
            return;
        }
        setTimeout(function () { QotD.init(cnt + 1) }, 1000);
    }
}

QotD.prevQuestions = function () {
    QotD.skip = QotD.skip + 1;
    QotD.getQuestions();
}

QotD.nextQuestions = function () {
    if (QotD.skip > 0) {
        QotD.skip = QotD.skip - 1;
    }
    QotD.getQuestions();
}

QotD.getQuestions = function () {
    HTTPReq.getJSON({
        url: "/tools/endpoints/qotd.bml?skip=" + QotD.skip,
        onData: QotD.printQuestions,
        onError: function (msg) { }
    });
}

QotD.printQuestions = function (data) {
    if (data.text) {
        $('all_questions').innerHTML = data.text;
    } else {
        QotD.skip = QotD.skip - 1;
    }
}

LiveJournal.register_hook("page_load", function () { QotD.init(1) });
