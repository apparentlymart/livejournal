DirectorySearchView = new Class(View, {
    init: function (viewElement) {
        DirectorySearchView.superClass.init.apply(this, [{view: viewElement}]);
        var searchConstraints = document.createElement("div");
        this.searchConstraintsView = new DirectorySearchConstraintsView({view: searchConstraints});

        var searchBtn = document.createElement("input");
        searchBtn.type = "button";
        searchBtn.value = "Search";
        DOM.addEventListener(searchBtn, "click", this.doSearch.bindEventListener(this));

        this.view.appendChild(searchConstraints);
        this.view.appendChild(searchBtn);
    },

    doSearch: function (evt) {
        var search = new DirectorySearch(this.searchConstraintsView.constraintsEncoded());
        search.doSearch();
    }
});

DirectorySearch = new Class(Object, {
    init: function (encodedSearchString) {
        this.searchstr = encodedSearchString;
    },

    doSearch: function (encodedSearchString) {
        if (encodedSearchString)
            this.searchstr = encodedSearchString;

        if (! this.searchstr) return false;

        var url = LiveJournal.getAjaxUrl("dirsearch");
        url += "?" + this.searchstr;

        var reqOpts = {
            "url": url,
            "method": "GET",
            "onData": this.gotResults.bind(this),
            "onError": this.gotError.bind(this)
        };

        HTTPReq.getJSON(reqOpts);

        // pop up a little searching window
        {
            var searchStatus = new LJ_IPPU("Searching...");
            var content = document.createElement("div");

            // infinite progress bar
            var pbarDiv = document.createElement("div");
            var pbar = new LJProgressBar(pbarDiv);
            pbar.setIndefinite(true);
            pbarDiv.style.width = "90%";
            pbarDiv.style.marginLeft = "auto";
            pbarDiv.style.marginRight = "auto";

            content.appendChild(_text("Trained monkeys blah blah blah"));
            content.appendChild(pbarDiv);

            searchStatus.setContentElement(content);
            searchStatus.setFadeIn(true);
            searchStatus.setFadeOut(true);
            searchStatus.setFadeSpeed(5);

            this.searchStatus = searchStatus;
            searchStatus.show();
        }
    },

    gotError: function (res) {
        if (this.searchStatus) this.searchStatus.hide();

        LiveJournal.ajaxError(res);
    },

    gotResults: function (results) {
        if (this.searchStatus) this.searchStatus.hide();

        if (! results) return;
        if (results.error) {
            LiveJournal.ajaxError(results.error);
            return;
        }

        var users = results.users;
        var resWindow = new DirectorySearchResults(users);
        resWindow.show();
    }
});
