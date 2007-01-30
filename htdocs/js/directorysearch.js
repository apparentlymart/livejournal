DirectorySearchView = new Class(View, {
    /* Usage:
              var dirSearchView = new DirectorySearchView(viewElement, opts);
              dirSearchView.search();

       Arguments:
               viewElement: what element to display the search constraints in
               opts[resultView]: what element to display the results in.
               if no view is provided a popup window will
               be used instead.
    */
    init: function (viewElement, opts) {
        // create a view with the constraints
        DirectorySearchView.superClass.init.apply(this, [{view: viewElement}]);
        var searchConstraints = document.createElement("div");
        this.searchConstraintsView = new DirectorySearchConstraintsView({view: searchConstraints});

        if (opts.resultsView)
            this.resultsView = opts.resultsView;

        // create the search button
        var searchBtn = document.createElement("input");
        searchBtn.type = "button";
        searchBtn.value = "Search";
        DOM.addEventListener(searchBtn, "click", this.search.bindEventListener(this));

        this.view.appendChild(searchConstraints);
        this.view.appendChild(searchBtn);
    },

    search: function (evt) {
        var search = new DirectorySearch(this.searchConstraintsView.constraintsEncoded(),
            {resultsView: this.resultsView});
        search.search();
    }
});

DirectorySearch = new Class(Object, {
    init: function (encodedSearchString, opts) {
        if (opts) this.resultsView = opts.resultsView;
        this.searchstr = encodedSearchString;
    },

    search: function (encodedSearchString) {
        if (encodedSearchString)
            this.searchstr = encodedSearchString;

        if (! this.searchstr) return false;

        var url = LiveJournal.getAjaxUrl("dirsearch");
        url += "?" + this.searchstr;

        this.ds = new JSONDataSource(url, this.gotResults.bind(this), {
            "onError": this.gotError.bind(this),
            "method" : "GET"
        });

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

            content.appendChild(_textSpan("Trained monkeys blah blah blah"));
            content.appendChild(pbarDiv);

            searchStatus.setContentElement(content);
            searchStatus.setFadeIn(true);
            searchStatus.setFadeOut(true);
            searchStatus.setFadeSpeed(5);

            this.searchStatus = searchStatus;
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
        users = users.sort(function (b, a) {
            return a.lastupdated - b.lastupdated;
        });

        var opts = new Object();
        if (this.resultsView) opts.resultsView = this.resultsView;

        var resWindow = new DirectorySearchResults(users, opts);
    }
});
