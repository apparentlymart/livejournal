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
                (opts && opts.resultsDisplay == "userpics" ? 25 : 100);
            this.page = opts && opts.page ? opts.page : 0;
        }

        this.render();
    },

    render: function () {
        var content = document.createElement("div");
        DOM.addClassName(content, "ResultsContainer");
        var self = this;

        // result count menu
        {
            var resultCountMenu = document.createElement("select");
            DOM.addClassName(resultCountMenu, "ResultCountMenu");

            // add items to menu
            [10, 25, 50, 100, 150, 200].forEach(function (ct) {
                var opt = document.createElement("option");
                opt.value = ct;
                opt.text = ct + " results";
                if (ct == self.resultsPerPage) {
                    opt.selected = true;
                }

                Try.these(
                          function () { resultCountMenu.add(opt, 0);    }, // IE
                          function () { resultCountMenu.add(opt, null); }  // Firefox
                          );
            });

            content.appendChild(_textSpan("Show "));
            content.appendChild(resultCountMenu);
            content.appendChild(_textSpan(" per page"));

            // add handler for menu
            var handleResultCountChange = function (e) {
                this.resultsPerPage = resultCountMenu.value;
                this.render();
            };
            DOM.addEventListener(resultCountMenu, "change", handleResultCountChange.bindEventListener(this));
        }

        // do pagination
        var pageCount   = Math.ceil(this.users.length / this.resultsPerPage); // how many pages
        var subsetStart = this.page * this.resultsPerPage; // where is the start index of this page
        var subsetEnd   = Math.min(subsetStart + this.resultsPerPage, this.users.length); // last index of this page

        var resultCount = _textDiv(this.users.length + " Results");
        DOM.addClassName(resultCount, "ResultCount");
        content.appendChild(resultCount);

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

            function pageLinkHandler (pageNum) {
                return function () {
                    self.page = pageNum;
                    self.render();
                };
            };

            for (var p = 0; p < pageCount; p++) {
                var pageLink = document.createElement("a");
                DOM.addClassName(pageLink, "PageLink");
                pageLink.innerHTML = p + 1;

                // install click handler on page #
                var self = this;
                DOM.addEventListener(pageLink, "click", pageLinkHandler(p));

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
