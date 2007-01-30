DirectorySearchResults = new Class(LJ_IPPU, {
    init: function (users, opts) {
        DirectorySearchResults.superClass.init.apply(this, ["Search Results"]);
        this.setFadeIn(true);
        this.setFadeOut(true);
        this.setFadeSpeed(5);
        this.users = users ? users : [];
        this.setDimensions("60%", "400px");

        // set up display options
        {
            this.picScale = 1;

            this.resultsDisplay = opts && opts.resultsDisplay ? opts.resultsDisplay : "userpics";
            this.resultsPerPage = opts && opts.resultsPerPage ? opts.resultsPerPage :
                (opts && opts.resultsDisplay == "userpics" ? 20 : 8);
            this.page = opts && opts.page ? opts.page : 0;
        }

        this.render();
    },

    render: function () {
        var content = document.createElement("div");
        DOM.addClassName(content, "ResultsContainer");

        // do pagination
        var pageCount   = Math.ceil(this.users.length / this.resultsPerPage); // how many pages
        var subsetStart = this.page * this.resultsPerPage; // where is the start index of this page
        var subsetEnd   = Math.min(subsetStart + this.resultsPerPage, this.users.length); // last index of this page

        log("Start: " + subsetStart + " end: " + subsetEnd + " resultsPerPage: " + this.resultsPerPage + " page: " + this.page);

        // render the users
        var usersContainer = document.createElement("div");
        DOM.addClassName(usersContainer, "UsersContainer");
        for (var i = subsetStart; i < subsetEnd; i++) {
            var userinfo = this.users[i];
            var userEle = this.renderUser(userinfo);
            if (! userEle) continue;

            DOM.addClassName(userEle, "User");
            usersContainer.appendChild(userEle);
        }
        content.appendChild(usersContainer);

        // print pages
        if (pageCount > 1) {
            var pages = document.createElement("div");
            DOM.addClassName(pages, "PageLinksContainer");

            var self = this;
            function pageLinkListener (pageNum) {
                return function () {
                    self.page = pageNum;
                    self.render();
                };
            };

            for (var p = 1; p < pageCount; p++) {
                var pageLink = document.createElement("a");
                DOM.addClassName(pageLink, "PageLink");
                pageLink.innerHTML = p;

                // install click handler on page #
                var self = this;
                DOM.addEventListener(pageLink, "click", pageLinkListener(p - 1));

                pages.appendChild(pageLink);
            }

            content.appendChild(pages);
        }

        this.setContentElement(content);

        // since a bunch of userpics and ljusers were created
        // we should reload contextualpopup so it can attach to them
        if (eval(defined(ContextualPopup)) && ContextualPopup.setup)
            ContextualPopup.setup();
    },

    renderUser: function (user) {
        var container = document.createElement("span");

        if (this.resultsDisplay == "userpic") {
            var upicContainer = document.createElement("div");
            DOM.addClassName(upicContainer, "UserpicContainer");

            if (user.url_userpic) {
                var upic = document.createElement("img");
                upic.src = user.url_userpic;
                DOM.addClassName(upic, "Userpic");
                upicContainer.appendChild(upic);
            }

            container.appendChild(upicContainer);
        }

        container.appendChild(_textSpan(user.ljuser_tag));
        var lastUpdated = _textDiv("Last updated " + user.lastupdated_string);
        DOM.addClassName(lastUpdated, "LastUpdated");
        container.appendChild(lastUpdated);

        return container;
    }
});
