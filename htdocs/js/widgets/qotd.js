var QotD = new Object();

QotD.init = function () {
    QotD.skip = 0;

    if (! $('prev_questions')) return;

    $('prev_questions').style.display = "inline";
    $('next_questions').style.display = "inline";
    DOM.addEventListener($('prev_questions'), "click", QotD.prevQuestions);
    DOM.addEventListener($('next_questions'), "click", QotD.nextQuestions);
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
        url: LiveJournal.getAjaxUrl("qotd"),
        method: "GET",
        data: HTTPReq.formEncoded({skip: QotD.skip }),
        onData: QotD.printQuestions,
        onError: function (msg) { }
    });
}

QotD.printQuestions = function (data) {
    if (data.text || QotD.skip == 0) {
        $('all_questions').innerHTML = data.text;
    } else {
        if (QotD.skip > 0) {
            QotD.skip = QotD.skip - 1;
        }
    }
}

LiveJournal.register_hook("page_load", QotD.init);
