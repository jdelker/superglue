/*
 * Drive the https://naming.ja.net/dns/ web site
 *
 * This site relies a lot on Javascript, which is why we are using
 * PhantomJS and CasperJS rather than trying to treat the web server
 * like a REST-ish API endpoint.
 *
 * We are mostly relying on element IDs for navigating the site. But the whole
 * thing smells of being generated with a complicated framework, so there is
 * little chance that these IDs will remain stable if the site is revised.
 *
 * Sadly I suspect this script will be rather fragile.
 */

"use strict";

var casper = require('casper').create({
    verbose: true,
});

var fs = require('fs');
var utils = require('utils');

var log_prefix = 'reg-push-janet: ';

function fail(msg) {
    throw new Error(log_prefix + msg);
}
function notice(msg) {
    casper.echo(log_prefix + msg);
}
function logfn(pri) {
    return function log(msg) {
	casper.log(log_prefix + msg, pri);
    }
}
var error = logfn('error');
var info  = logfn('info');
var debug = logfn('debug');

function usage() {
    console.log(
'usage: casperjs [--log-level=<level>] reg-push-janet.js\n'+
'                [--ignore-tickets] [--ignore-match]\n'+
'                 --creds=<file> --domain=<domain> --delegation=<file>\n'+
'	--log-leve=<level>	Set "info" or "debug" mode\n'+
'	--ignore-tickets	Update even if the domain has pending tickets\n'+
'	--ignore-match		Update even if its delegation matches\n'+
'	--creds=<file>		Path to credentials file\n'+
'	--domain=<domain>	The domain to update\n'+
'	--delegation=<file>	File containing delegation records\n'+
'\n'+
'The credentials file may contain blank lines or lines starting with a "#"\n'+
'to mark comments. The other lines have the form "<keyword><space><value>".\n'+
'There must be lines containing the keywords "user" and "pass".\n'+
'\n'+
'The delegation file is in standard DNS Master File format with the origin\n'+
'set to the domain being updated. It must contain NS records for the zone;\n'+
'it may contain DS records and/or glue address records. TTLs are ignored.\n'+
'$ directives, \\ escapes, "strings", and () continuations are not supported.\n'
);
    phantom.exit(1);
}

var re_dname = /^(?:[a-z0-9][a-z0-9-]*[a-z0-9][.])+[a-z0-9][a-z0-9-]*[a-z0-9]$/;

var domain = casper.cli.options.domain;
if (!domain || !domain.match(re_dname)) usage();

var delegation = (function load_delegation() {
    var d = { NS: {}, DS: '', addr: {} };
    var owner = domain;
    var file = casper.cli.options.delegation;
    if (!file) usage();
    var stream = fs.open(file, 'r');
    for (var n = 1; !stream.atEnd(); n++) {
	function syntax(msg) {
	    fail(file+':'+n+': '+msg);
	}
	function parse_dname(n) {
	    if (n === '@')
		return domain;
	    if (n.match(/\.$/))
		n = n.replace(/\.$/, '');
	    else
		n = n+'.'+domain;
	    if (n.match(re_dname))
		return n;
	    syntax('bad domain name '+n);
	}
	var line = stream.readLine();
	line = line.replace(/;.*/, '');
	if (line.match(/^\s*$/))
	    continue;
	var match = line.match(/^(\S*)\s+(?:(?:IN|\d+)\s+)*(NS|DS|A|AAAA)\s+(.*)$/);
	if (!match)
	    syntax('could not parse line '+line);
	var rdata = match[3];
	var type = match[2];
	if (match[1] !== '')
	    owner = parse_dname(match[1]);
	switch (type) {
	case 'NS':
	    if (owner !== domain)
		syntax('NS RRs must be owned by '+domain);
	    rdata = parse_dname(rdata);
	    d.NS[rdata] = true;
	    debug(domain+'. NS '+rdata);
	    continue;
	case 'DS':
	    if (owner !== domain)
		syntax('DS RRs must be owned by '+domain);
	    // TODO: sanity check rdata
	    var ds = owner+'. IN DS '+rdata;
	    d.DS = d.DS + ds + '\n';
	    debug(ds);
	    continue;
	case 'A':
	    if (owner.substr(-domain.length) !== domain)
		syntax('glue A records must be subdomains of '+domain);
	    if (!rdata.match(/^\d+\.\d+\.\d+\.\d+$/))
		syntax('bad IPv4 address: '+rdata);
	    if (!(owner in d.addr))
		d.addr[owner] = [];
	    d.addr[owner].push(rdata);
	    debug(owner+'. A '+rdata);
	    continue;
	case 'AAAA':
	    if (owner.substr(-domain.length) !== domain)
		syntax('glue AAAA records must be subdomains of '+domain);
	    if (!rdata.match(/^[0-9a-f:]+$/))
		syntax('bad IPv6 address: '+rdata);
	    if (!(owner in d.addr))
		d.addr[owner] = [];
	    d.addr[owner].push(rdata);
	    debug(owner+'. AAAA '+rdata);
	    continue;
	}
    }
    var ns = d.NS.keys();
    d.count = ns.length;
    if (!(d.count > 0))
	fail(file+': no delegation records found');
    for (var s in d.addr) {
	if (!d.NS[s])
	    fail(file+': glue records for nonexistent NS '+s);
	d.addr[s].sort();
	d.count += d.addr[s].length - 1;
    }
    debug('name server count '+d.count);
    d.NS = ns.sort();
    return d;
})();

var creds = (function load_creds() {
    var c = {};
    var file = casper.cli.options.creds;
    if (!file) usage();
    var stream = fs.open(file, 'r');
    for (var n = 1; !stream.atEnd(); n++) {
	var line = stream.readLine();
	if (line.match(/^\s*#|^\s*$/))
	    continue;
	var match = line.match(/^(\S+)\s+(.*)$/)
	if (!match)
	    fail('read '+file+':'+n+': could not parse line: '+line);
	c[match[1]] = match[2];
	if (match[1] === 'pass')
	    debug('pass ********');
	else
	    debug(match[1]+" "+match[2]);
    }
    return c;
})();

casper.start('https://naming.ja.net/dns');

casper.then(function login() {
    info("Loaded login page: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_Login1_UserName': creds.user,
	'#MainContent_Login1_Password': creds.pass,
    });
    this.click('#MainContent_Login1_LoginButton');
});

casper.then(function greeting() {
    if (this.getTitle() !== 'Home Page')
	fail('Login failed')
    info("Loaded greeting page: " + this.getTitle());
    this.click('#commonActionsMenu_ListPendingTickets');
});

casper.then(function view_tickets() {
    info("Loaded tickets: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_DomainFilterInput': domain
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function find_tickets() {
    info("Loaded filtered tickets: " + this.getTitle());
    var clicky = true;
    if (this.exists('#MainContent_TicketListView_CurrentPageLabel')) {
	info('Changes pending for ' + domain);
	if (casper.cli.options['ignore-tickets'])
	    info('Ignoring tickets');
	else
	    clicky = false
    }
    if (clicky)
	this.click('#commonActionsMenu_ListDomains');
    else
	this.exit(0);
});

casper.then(function choose_domain() {
    info("Loaded domain list: " + this.getTitle());
    this.fillSelectors('form', {
	'#MainContent_tbDomainNames': domain
    });
    this.click('#MainContent_btnFilter');
});

casper.then(function find_domain() {
    info("Loaded filtered list: " + this.getTitle());
    for (var i = 0; ; i++) {
	var sel = '#MainContent_DomainListView_ViewDomainNumber'+i+'_'+i;
	if (!this.exists(sel))
	    fail('Could not find domain: ' + domain);
	// Unfortunately there isn't a sensible selector for each row of the
	// search results table, so we have to dig around for the cousin node
	// which might contain the name of the domain we are looking for.
	var res = this.evaluate(function find_domain(sel) {
	    var a = document.querySelector(sel);
	    var tr = a.parentNode.parentNode;
	    var td = tr.childNodes[3];
	    return td.innerHTML.toLowerCase();
	}, sel);
	info('Found domain: ' + res);
	if (res === domain) {
	    this.click(sel);
	    break;
	}
    }
});

var got_ns = [];

casper.then(function open_domain() {
    info("Loaded domain details: " + this.getTitle());
    var tbl = this.getElementsInfo('#MainContent_nameServersTab td');
    for (var j = 0, i = 0; i < tbl.length; i++) {
	var td = tbl[i].text;
	if (td.match(re_dname)) {
	    got_ns[j++] = td;
	}
    }
    got_ns.sort();
    var match = true;
    for (var i = 0; i < got_ns.length; i++) {
	if (got_ns[i] !== set_ns[i])
	    match = false;
    }
    if (match && got_ns.length === set_ns.length) {
	info('No need to modify delegation of ' + domain)
	this.exit(0);
    } else {
	info('Modifying delegation of ' + domain)
	this.click('#MainContent_ModifyDomainButton');
    }
});

var nsec_id = '#MainContent_NumberOfSecServers';
function get_nsec() {
    return casper.getElementInfo(nsec_id + ' option[selected]').text;
}
function report_nsec() {
    var nsec = get_nsec();
    info('Number of secondaries for ' + domain + ' is ' + nsec);
    return nsec;
}

casper.then(function set_number_of_secondaries() {
    info("Loaded page: " + this.getTitle());
    var nsec = report_nsec();
    var form = {};
    form[nsec_id] = set_ns.length - 1;
    if (form[nsec_id] !== nsec)
	this.fillSelectors('form', form);
});

function twoDigit(n) {
    if (n < 10) return '0' + n;
    else return '' + n;
}
function HH_MM(d) {
    return twoDigit(d.getHours())+':'+twoDigit(d.getMinutes());
}
function dd_mm_yyyy(d) {
    return twoDigit(d.getDate()) + '/' +
	   twoDigit(d.getMonth()+1) + '/' + d.getFullYear();
}
function set_form_time(form, time, today) {
    var t = time.text;
    var tv = time.attributes.value;
    var d = dd_mm_yyyy(new Date(Date.now() +
				(today ? 0 : 24 * 60 * 60 * 1000)));
    var dd = today ? 'today' : 'tomorrow';
    form['#MainContent_ModificationTime'] = tv;
    form['#MainContent_ModificationDateCalendar'] = d;
    notice('Modification scheduled at '+t+' '+d+' '+dd+' for '+domain);
    notice('Old NS RRset');
    for (var i = 0; i < got_ns.length; i++)
	notice(domain + ' NS ' + got_ns[i]);
    notice('New NS RRset');
    for (var i = 0; i < set_ns.length; i++)
	notice(domain + ' NS ' + set_ns[i]);
}

casper.waitForSelector('#MainContent_SecAddress'+(set_ns.length-2),
function set_nameservers() {
    var n = set_ns.length;
    if (report_nsec() !== ''+(n-1))
	fail('Unable to resize nameserver form for ' + domain);
    var form = {}
    form['#MainContent_PrimeNameserverName'] = set_ns[n-1];
    for (var i = 0; i < n-1; i++)
	form['#MainContent_SecAddress'+i] = set_ns[i];
    var now = HH_MM(new Date(Date.now() + 5 * 60 * 1000));
    var today = false;
    var times = this.getElementsInfo('#MainContent_ModificationTime option');
    for (var i = 0; i < times.length; i++) {
	if (now < times[i].text) {
	    set_form_time(form, times[i], today = true);
	    break;
	}
    }
    if (!today) {
	set_form_time(form, times[0], today = false);
    }
    this.fillSelectors('form', form);
    this.click('#MainContent_ConfirmRequest');
},
function onTimeout() {
    fail('Timeout while filling modification form for ' + domain);
});

casper.waitForUrl(/ViewPendingTickets/,
function change_submitted() {
    if (this.exists('#MainContent_SubmissionText')) {
	notice(this.getElementInfo('#MainContent_SubmissionText').text);
	this.exit(0);
    } else {
	this.echo(this.page.plainText);
	fail('Unexpected response after submbitting modification for ' + domain);
    }
},
function onTimeout() {
    fail('Timeout after submitting modification for ' + domain);
});

casper.run();
