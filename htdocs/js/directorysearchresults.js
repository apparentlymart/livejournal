DirectorySearchResults = new Class(LJ_IPPU, {
    init: function (users) {
        DirectorySearchResults.superClass.init.apply(this, ["Search Results"]);
        this.setFadeIn(true);
        this.setFadeOut(true);
        this.setFadeSpeed(5);
        this.users = users ? users : [];
        this.render();
    },

    render: function () {
        var content = document.createElement("div");
        for (var i = 0; i < this.users.length; i++) {
            content.innerHTML += inspect(this.users[i]);
        }

        this.setContentElement(content);
    }
});
