// a directory search constraint
var DirectorySearchConstraint = new Class(Object, {
  init: function (type, opts) {
    type = type ? type : '';
    this.type = type;
    this.fields = {};

    if (opts) {
        this.fieldValues = opts.values ? opts.values : {};
    };

    this.rendered = false;
  },

  render: function () {
    if (this.constraintContainer) {
      this.renderExtraFields();
    } else {
      var constraintContainer = document.createElement("span");
      DOM.addClassName(constraintContainer, "Constraint");
      this.constraintContainer = constraintContainer;

      var extraFields = document.createElement("div");
      DOM.addClassName(extraFields, "ConstraintFields");
      constraintContainer.appendChild(extraFields);
      this.extraFields = extraFields;
      this.renderExtraFields();
    }

    return this.constraintContainer;
  },

  typeChanged: function (evt) {
    var menu = evt.target;
    if (! menu || menu.tagName.toUpperCase() != "SELECT") return;

    var selIndex = menu.selectedIndex;
    if (selIndex == -1) {
      this.type = null;
    } else {
      this.type = menu.value;
    }

    this.render();

    return false;
  },

  renderExtraFields: function () {
    this.extraFields.innerHTML = "";

    if (! this.type) return;

    this.fields = {};
    this.override(DirectorySearchConstraintPrototypes[this.type]);
    this.extraFields.innerHTML = "";
    this.renderFields(this.extraFields);
    this.setFieldDefaultValues();
  },

  setFieldDefaultValues: function () {
      // set default field values if they exist
      if (! this.fieldNames) return;

      var self = this;
      this.fieldNames.forEach(function (field) {
          if (self.fieldValues[field] && self.fields[field])
              self.fields[field].value = self.fieldValues[field];
      });
  },

  // returns a urlencoded representation of this constraint
  asString: function () {
    var fieldNames = this.fieldNames;
    if (! fieldNames) return "";

    var fields = {};

    var self = this;
    fieldNames.forEach(function (fieldName) {
      fields[fieldName] = self.fields[fieldName].value;
    });

    return HTTPReq.formEncoded(fields);
  }

});

// the main view that contains the constraints
var DirectorySearchConstraintsView = new Class(View, {

  init: function (opts) {
    DirectorySearchConstraintsView.superClass.init.apply(this, arguments);
    this.constraints = [];

    // create a view for storing the constraints
    this.constraintsView = document.createElement("div");
    DOM.addClassName(this.constraintsView, "Constraints");
    this.view.appendChild(this.constraintsView);

    // start with empty constraint
    this.addConstraint('Interest', {values: {"int_like": "mac dre"}});
    this.addConstraint();
  },

  renderNewConstraint: function (c) {
    var self = this;

    // get the constraint's rendered self
    var constraintElement = c.render();
    if (! constraintElement) return;
    /////////////////////////////////////

    // create container for this constraint
    var constraintContainer = document.createElement("div");
    DOM.addClassName(constraintContainer, "ConstraintContainer");
    constraintContainer.appendChild(constraintElement);
    ///////////////////////////////////////

    // build the constraint type menu
    var typeMenu = document.createElement("select");
    DirectorySearchConstraintTypes.forEach(function (type) {
      var displayName = DirectorySearchConstraintPrototypes[type] &&
        DirectorySearchConstraintPrototypes[type].displayName ?
        DirectorySearchConstraintPrototypes[type].displayName :
        type;

      var typeOpt = document.createElement("option");
      typeOpt.value = type;
      typeOpt.text = displayName;
      if (type == c.type) {
        typeOpt.selected = true;
      }

      Try.these(
                function () { typeMenu.add(typeOpt, 0);    }, // IE
                function () { typeMenu.add(typeOpt, null); }  // Firefox
                );
    });
    DOM.addEventListener(typeMenu, "change", c.typeChanged.bindEventListener(c));
    /////////////////////////////////

    // add/remove buttons
    var removeButton = document.createElement("input");
    removeButton.type = "button";

    var addButton = document.createElement("input");
    addButton.type = "button";

    addButton.value = "+";
    removeButton.value = "-";
    DOM.addEventListener(addButton, "click", self.addConstraintHandler.bindEventListener(self));
    DOM.addEventListener(removeButton, "click", function (evt) {
      if (self.constraints.length <= 1) return false;

      self.constraintsView.removeChild(constraintContainer);
      self.constraints.remove(c);
      return false;
    });
    var btnContainer = document.createElement("span");
    DOM.addClassName(btnContainer, "ConstraintModifyButtons");
    btnContainer.appendChild(removeButton);
    btnContainer.appendChild(addButton);
    //////////////////////

    constraintContainer.appendChild(typeMenu);
    constraintContainer.appendChild(constraintElement);
    constraintContainer.appendChild(btnContainer);
    self.constraintsView.appendChild(constraintContainer);
  },

  addConstraintHandler: function (evt) {
    this.addConstraint();
    return false;
  },

  addConstraint: function (type, opts) {
      var c = new DirectorySearchConstraint(type, opts);
      this.constraints.push(c);
      this.renderNewConstraint(c);
  },

  reset: function () {
    this.constraints.empty();
  },

  constraintsEncoded: function () {
    var ce = [];
    this.constraints.forEach(function (c) {
      var encoded = c.asString();
      if (encoded) ce.push(encoded);
    });
    return ce.join("&");
  }

});


//////// Constraint classes
var DirectorySearchConstraintTypes = [
                                      "",
                                      "Age",
                                      "Interest",
                                      "UpdateTime"
];

var DirectorySearchConstraintPrototypes = {
  Age: {
    renderFields: function (content) {
      var lowBound = document.createElement("input");
      lowBound.size = 3;
      lowBound.maxLength = 3;
      var highBound = lowBound.cloneNode(false);

      this.fields.age_min = lowBound;
      this.fields.age_max = highBound;

      var t = _textSpan("between ", " and ", " years old");
      [t[0], lowBound, t[1], highBound, t[2]].forEach(function (ele) {
        content.appendChild(ele);
      });
    },
    fieldNames: ["age_min", "age_max"]
  },

  Interest: {
    renderFields: function (content) {
      var interest = document.createElement("input");
      this.fields.int_like = interest;
      content.appendChild(interest);
    },
    fieldNames: ["int_like"]
  },

  UpdateTime: {
    renderFields: function (content) {
      var t = _textSpan("Updated in the last ", " day(s)");
      var days = document.createElement("input");
      this.fields.ut_days = days;

      [t[0], days, t[1]].forEach(function (ele) { content.appendChild(ele) });
    },
    fieldNames: ["ut_days"],
    displayName: "Time last updated"
  }

};
