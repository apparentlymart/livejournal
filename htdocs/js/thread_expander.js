
	window.threadExpanders	= []

	function threadExpander( url, id, srcObj )
	{

		this.url			= url.replace( /#.*$/, '' )
		this.threadId		= id
		this.caller			= srcObj
		this.destination	= document.getElementById( 'expand' + id )
		this.id				= window.threadExpanders.length

		window.threadExpanders.push( this )
		return this.get()
	}


	threadExpander.prototype.get	= function()
	{
		var thisTE		= this

		this.inProgress( true )
		if (browser.isIE)
			this.iObj		= document.createElement('<iframe onload="threadExpanders['+this.id+'].parse()" src="'+this.url+'" style="width:1px;height:1px;disaply:none;">')
		else
		{
			this.iObj		= document.createElement('iframe')
			with (this.iObj.style)
			{
				height	= '1px'
				widht	= '1px'
				display	= 'none'
			}
			this.iObj.onload	= function() { return thisTE.parse() }
			this.iObj.src		= this.url
		}

		document.body.appendChild( this.iObj )
		return true
	}

	threadExpander.prototype.parse	= function()
	{
		var iDoc	= this.iObj.contentDocument || this.iObj.contentWindow
		if (iDoc.document)
			iDoc	= iDoc.document

		var comment	= iDoc.getElementById( 'expand' + this.threadId )
		if (comment)
		{
			this.destination.innerHTML	= comment.innerHTML
            for (var k in this.iObj.contentWindow.LJ_cmtinfo)
                LJ_cmtinfo[k] = this.iObj.contentWindow.LJ_cmtinfo[ k ]
            ContextualPopup.setup()
		}

		this.iObj.parentNode.removeChild( this.iObj )
		return true
	}

	threadExpander.prototype.inProgress	= function( inProgress )
	{
		if (inProgress)
			this.caller.appendChild
			(
				document.getElementById('thread_loader_img').firstChild.cloneNode( false )
			)
		return true
	}

