CalendarLite = function(canvas) {
	this.onselect = function(){};
	this.now = new Date();
	
	this.canvas = canvas;
	this.cells = canvas.getElementsByTagName('table')[0].tBodies[0].getElementsByTagName('td');
	
	var y_node = DOM.getElementsByClassName(this.canvas, 'year')[0],
		m_node = DOM.getElementsByClassName(this.canvas, 'month')[0];
	
	this.briefY = DOM.getElementsByClassName(y_node, 'caption')[0];
	this.briefM = DOM.getElementsByClassName(m_node, 'caption')[0];
	this.is_show = false;
	this.current_year  = this.now.getFullYear();
	this.current_month = this.now.getMonth();
	this.current_day   = this.now.getDate();
	this.value = (new Date(this.current_year, this.current_month, this.current_day)).valueOf();
	
	this.todayDate = new Date(this.now.getFullYear(), this.now.getMonth(), this.now.getDate());
	
	DOM.addEventListener(canvas, 'click', (function(e) {
		Event.stop(e);
	}).bindEventListener(this));
	
	DOM.addEventListener(document, 'click', (function() {
		this.hide();
	}).bindEventListener(this));
	
	DOM.addEventListener(DOM.getElementsByClassName(m_node, 'rarr')[0], 'click', (function() {
		this.current_month++;
		this.fill();
	}).bindEventListener(this));
	DOM.addEventListener(DOM.getElementsByClassName(m_node, 'larr')[0], 'click', (function() {
		this.current_month--;
		this.fill();
	}).bindEventListener(this));
	
	DOM.addEventListener(DOM.getElementsByClassName(y_node, 'rarr')[0], 'click', (function() {
		this.current_year++;
		this.fill();
	}).bindEventListener(this));
	DOM.addEventListener(DOM.getElementsByClassName(y_node, 'larr')[0], 'click', (function() {
		this.current_year--;
		this.fill();
	}).bindEventListener(this));
	
	this.fill();
	
	return this;
}

CalendarLite.prototype.fillNow = function() {
	this.fill(this.now.getFullYear(), this.now.getMonth());
}

CalendarLite.prototype.fill = function(cur_year, cur_month, cur_day) {
	switch(arguments.length) {
		case 1:
			this.current_year = Number(cur_year);
			break;
		case 2:
			this.current_year = Number(cur_year);
			this.current_month = Number(cur_month);
			break;
		case 3:
			this.current_year = Number(cur_year);
			this.current_month = Number(cur_month);
			this.current_day = Number(cur_day);
			break;
	}
	
	var i_date = new Date(this.current_year, this.current_month, 1),
		day_shift = i_date.getDay();
	
	this.current_year = i_date.getFullYear();
	this.current_month = i_date.getMonth();
	
	this.briefY.innerHTML = i_date.getFullYear();
	this.briefM.innerHTML = CalendarLite.months[i_date.getMonth()];
	
	day_shift = day_shift == 0 ? 6 : day_shift - 1;
	i_date.setDate(1 - day_shift);
	
	var i = -1, cell, f, t = this;
	while(this.cells[++i]) {
		cell = this.cells[i];
		
		DOM.removeClassName(cell, 'selected');
		DOM.removeClassName(cell, 'past');
		DOM.removeClassName(cell, 'today');
		if(this.current_month % 12 !== i_date.getMonth())
			DOM.addClassName(cell, 'dif');
		else
			DOM.removeClassName(cell, 'dif');

		if(this.todayDate.getTime() > i_date.getTime())
			DOM.addClassName(cell, 'past');
		else if(this.todayDate.getTime() == i_date.getTime()){
			DOM.addClassName(cell, 'today');
		}

		cell.data = i_date.valueOf();
		cell.data_date = i_date.getDate();
		cell.setAttribute('date', cell.data);
		
		if(cell.data == this.value) {
			DOM.addClassName(cell, 'selected');
			cell.innerHTML = '<strong>' + i_date.getDate() + '</strong>';
		} else {
			cell.innerHTML = i_date.getDate();
		}
		
		(function(i_date) {
			cell.onclick = function() {
				t.select(i_date);
			}
		})(new Date(i_date));
		
		i_date.setDate(i_date.getDate() + 1);
	}

	var test_cell = this.cells[this.cells.length-1];
	if(test_cell.data_date <= 6) {
		DOM.removeClassName(test_cell.parentNode, 'hide');
	} else {
		DOM.addClassName(test_cell.parentNode, 'hide');
	}
	return this;
}

CalendarLite.prototype.select = function(data) {
	if(typeof data == 'string') {
		data = new Date(data).valueOf();
	}
	
	this.value = (new Date(data.getFullYear(), data.getMonth(), data.getDate())).valueOf();
	
	this.hide();
	Array.prototype.forEach.call(this.cells, function($1) {
		if($1.data == data){
			DOM.addClassName('selected',$1);
		}
	})
	this.onselect(data);
	return this;
}

CalendarLite.prototype.show = function(){
	this.is_show = true;
	DOM.removeClassName(this.canvas, 'hide');
	this.fill();
}

CalendarLite.prototype.hide = function(){
	this.is_show = false;
	DOM.addClassName(this.canvas, 'hide');
}
