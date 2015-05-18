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
var system = require('system');
var utils = require('utils');

var log_prefix = 'superglue-janet: ';

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
'usage: casperjs [--log-level=<level>] superglue-janet.js\n'+
'                [--ignore-tickets] [--ignore-match] [--not-really]\n'+
'                 --creds=<file> <domain>\n'+
'	--log-leve=<level>	Set "info" or "debug" mode\n'+
'	--ignore-tickets	Update even if the domain has pending tickets\n'+
'	--ignore-match		Update even if its delegation matches\n'+
'	--not-really		Stop at the last moment\n'+
'	--creds=<file>		Path to credentials file\n'+
'	<domain>		The domain to update\n'+
'	stdin			Delegation records\n'
);
    phantom.exit(1);
}

var re_dname = /^(?:[a-z0-9][a-z0-9-]*[a-z0-9][.])+[a-z0-9][a-z0-9-]*[a-z0-9]$/;
var re_ipv6 = /^(?:[0-9a-f]{1,4}:)+(?::|(?::[0-9a-f]{1,4})+|[0-9a-f]{1,4})$/;
var re_ipv4 = /^\d+\.\d+\.\d+\.\d+$/;

function ns_cmp(a,b) {
    if (a.name < b.name) return -1;
    if (a.name > b.name) return +1;
    if (a.addr < b.addr) return -1;
    if (a.addr > b.addr) return +1;
    return 0;
}

if (casper.cli.args.length !== 1) usage();
var domain = casper.cli.args[0];
if (!domain.match(re_dname)) usage();

var delegation = (function load_delegation() {
    var d = { NS: {}, DS: '', addr: {} };
    var owner = domain;
    var stream = system.stdin;
    for (var n = 1; !stream.atEnd(); n++) {
	var syntax = function syntax(msg) {
	    fail(file+':'+n+': '+msg);
	}
	var parse_dname = function parse_dname(n) {
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
	    debug('parse '+domain+' NS '+rdata);
	    continue;
	case 'DS':
	    if (owner !== domain)
		syntax('DS RRs must be owned by '+domain);
	    // TODO: sanity check rdata?
	    var ds = owner+'. IN DS '+rdata;
	    d.DS = d.DS + ds;
	    debug('parse '+ds);
	    continue;
	case 'A':
	    if (owner.substr(-domain.length) !== domain)
		syntax('glue A records must be subdomains of '+domain);
	    if (!rdata.match(re_ipv4))
		syntax('bad IPv4 address: '+rdata);
	    if (!(owner in d.addr))
		d.addr[owner] = [];
	    d.addr[owner].push(rdata);
	    debug('parse '+owner+' A '+rdata);
	    continue;
	case 'AAAA':
	    if (owner.substr(-domain.length) !== domain)
		syntax('glue AAAA records must be subdomains of '+domain);
	    if (!rdata.match(re_ipv6))
		syntax('bad IPv6 address: '+rdata);
	    if (!(owner in d.addr))
		d.addr[owner] = [];
	    d.addr[owner].push(rdata);
	    debug('parse '+owner+' AAAA '+rdata);
	    continue;
	}
    }
    var ns = Object.keys(d.NS);
    if (ns.length === 0 && d.DS === '')
	fail(file+': no delegation records found');
    var nsa = [];
    for (var s in d.addr) {
	if (!d.NS[s])
	    fail(file+': glue records for nonexistent NS '+s);
    }
    for (var i = 0; i < ns.length; i++) {
	if (ns[i].substr(-domain.length) === domain) {
	    var a = d.addr[ns[i]];
	    if (!a) fail(file+': glue records missing for NS '+ns[i]);
	    for (var j = 0; j < a.length; j++)
		nsa.push({ name: ns[i], addr: a[j] });
	} else {
	    if (d.addr[ns[i]])
		fail(file+': spurious glue records for NS '+ns[i]);
	    nsa.push({ name: ns[i], addr: '' });
	}
    }
    d.NS = nsa.sort(ns_cmp);
    d.addr = undefined;
    debug('name server count '+d.NS.length);
    for (var i = 0; i < d.NS.length; i++)
	debug(domain+' ns '+d.NS[i].name+' glue '+d.NS[i].addr);
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
	    if (tr.childNodes[4].innerHTML === 'Delegated')
		return tr.childNodes[3].innerHTML.toLowerCase();
	}, sel);
	info('Found domain: ' + res);
	if (res === domain) {
	    this.click(sel);
	    break;
	}
    }
});

casper.then(function open_domain() {
    info("Loaded domain details: " + this.getTitle());
    var tbl = this.getElementsInfo('#MainContent_nameServersTab td');
    // current name servers
    var cns = [];
    for (var j = 0, i = 0; i < tbl.length; i++) {
	var td = tbl[i].text;
	if (td.match(re_ipv6) || td.match(re_ipv4)) {
	    cns[j-1].addr = td;
	} else if (td.match(re_dname)) {
	    cns[j++] = { name: td, addr: '' };
	}
    }
    cns.sort(ns_cmp);
    for (var i = 0; i < cns.length; i++)
	debug(domain+' ns '+cns[i].name+' glue '+cns[i].addr);
    var ds = '';
    if (this.exists('#MainContent_DsKeysDisplay')) {
	ds = this.getElementInfo('#MainContent_DsKeysDisplay').text;
	debug(ds);
    } else {
	debug('no DS records');
    }
    // desired name servers
    var dns = delegation.NS;
    var match = !casper.cli.options['ignore-match'];
    if (cns.length !== dns.length && dns.length !== 0)
	match = false;
    else
	for (var i = 0; i < dns.length; i++)
	    if (ns_cmp(cns[i], dns[i]))
		match = false;
    if (ds !== delegation.DS && delegation.DS !== '')
	match = false;
    if (match) {
	info('No need to modify delegation of ' + domain)
	this.exit(0);
    } else {
	info('Modifying delegation of ' + domain)
	if (dns.length) {
	    notice('Old NS records');
	    for (var i = 0; i < cns.length; i++)
		notice(domain+' ns '+cns[i].name+' glue '+cns[i].addr);
	    notice('New NS records');
	    for (var i = 0; i < dns.length; i++)
		notice(domain+' ns '+dns[i].name+' glue '+dns[i].addr);
	}
	if (delegation.DS !== '') {
	    notice('Old DS records');
	    notice(ds);
	    notice('New DS records');
	    notice(delegation.DS);
	}
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
    if (delegation.NS.length > 0) {
	form[nsec_id] = delegation.NS.length - 1;
	if (form[nsec_id] !== nsec)
	    this.fillSelectors('form', form);
    }
});

var ds_id = '#MainContent_DsKeyTabContainer_DsPasteTab_DsKeyText';

casper.waitForSelector(delegation.NS.length === 0 ? '#form1' :
	'#MainContent_SecAddress'+(delegation.NS.length-2),
function expand_ds_form() {
    if (delegation.DS !== '' &&	!this.exists(ds_id))
	this.click('#ModifyDsKeyIcon input');
},
function onTimeout() {
    fail('Timeout while adjusting nameserver form for ' + domain);
});

casper.waitForSelector(delegation.DS === '' ? '#form1' : ds_id,
	set_delegation, // see below
function onTimeout() {
    fail('Timeout while expanding DS form for ' + domain);
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
}

function set_delegation() {
    var form = {}
    var ns = delegation.NS;
    var n = ns.length;
    if (n > 0) {
	if (report_nsec() !== ''+(n-1))
	    fail('Unable to resize nameserver form for ' + domain);
	form['#MainContent_PrimeNameserverName'] = ns[0].name;
	form['#MainContent_PrimeNameserverIp']   = ns[0].addr;
	for (var i = 0; i < n-1; i++) {
	    form['#MainContent_SecAddress'+i] = ns[i+1].name;
	    form['#MainContent_SecIp'+i]      = ns[i+1].addr;
	}
    }
    if (delegation.DS !== '') {
	form[ds_id] = delegation.DS;
    }
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
    if (casper.cli.options['not-really']) {
	notice('Not really!');
	this.exit(0);
    } else {
	this.click('#MainContent_ConfirmRequest');
    }
}

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
