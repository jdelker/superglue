/*
 * Drive the https://domainregistry.jisc.ac.uk/dns/ web site for whois updates
 */

"use strict";

var casper = require('casper').create({
    verbose: true,
    exitOnError: true,
});

var fs = require('fs');
var system = require('system');
var utils = require('utils');

var log_prefix = 'whois-up-janet: ';

function quit(x) {
    casper.exit(x);
    casper.bypass(999);
}

function fail(msg) {
    casper.echo(log_prefix + msg);
    phantom.exit(1);
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
'usage: casperjs [--log-level=<level>] whois-up-janet.js\n'+
'                [--ignore-tickets] [--ignore-match] [--not-really]\n'+
'                [--whois=<file>] --creds=<file> <domain>\n'+
'	--log-level=<level>	Set "info" or "debug" mode\n'+
'	--ignore-tickets	Update even if the domain has pending tickets\n'+
'	--ignore-match		Update even if its delegation matches\n'+
'	--not-really		Stop at the last moment\n'+
'	--whois=<file>		whois contact details in JSON\n'+
'	--creds=<file>		Path to credentials file\n'+
'	<domain>		The domain to update\n'
);
    quit(1);
}

var re_dname = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?[.])+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
var re_ipv6 = /^(?:[0-9a-f]{1,4}:)+(?::|(?::[0-9a-f]{1,4})+|[0-9a-f]{1,4})$/;
var re_ipv4 = /^\d+\.\d+\.\d+\.\d+$/;

function ns_cmp(a,b) {
    if (a.name < b.name) return -1;
    if (a.name > b.name) return +1;
    if (a.addr < b.addr) return -1;
    if (a.addr > b.addr) return +1;
    return 0;
}

function ns_show(prt, ns) {
    for (var i = 0; i < ns.length; i++)
	if (ns[i].addr)
	    prt(domain+' ns '+ns[i].name+' glue '+ns[i].addr);
	else
	    prt(domain+' ns '+ns[i].name);
}

if (casper.cli.args.length !== 1) usage();
var domain = casper.cli.args[0].toLowerCase();
if (!domain.match(re_dname)) usage();

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

var registrant = (function load_registrant() {
    var file = casper.cli.options.whois;
    if (!file)
	return {};
    var r = JSON.parse(fs.read(file));
    for (var k in r) {
	debug(k + ": " + r[k]);
    }
    return r;
})();

var delegation = (function load_delegation() {
    var d = { NS: {}, DS: '', addr: {} };
    var owner = domain;
    var stream = system.stdin;
    for (var n = 1; !stream.atEnd(); n++) {
	var syntax = function syntax(msg) {
	    fail(domain+':'+n+': '+msg);
	}
	var parse_dname = function parse_dname(n) {
	    if (n === '@')
		return domain;
	    if (n.match(/\.$/))
		n = n.replace(/\.$/, '');
	    else
		n = n+'.'+domain;
	    n = n.toLowerCase();
	    if (n.match(re_dname))
		return n;
	    syntax('bad domain name '+n);
	}
	var line = stream.readLine();
	line = line.replace(/;.*/, '');
	if (line.match(/^\s*$/))
	    continue;
	var match = line.match(/^(\S*)\s+(?:(?:IN|\d+)\s+)*(NS|DS|DNSKEY|A|AAAA)\s+(.*?)\s*$/);
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
	case 'DNSKEY':
	    if (owner !== domain)
		syntax('DNSKEY RRs must be owned by '+domain);
	    // ignore
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
//    if (ns.length === 0 && d.DS === '')
//	fail(domain+': no delegation records in input');
    var nsa = [];
    for (var s in d.addr) {
	if (!d.NS[s])
	    fail(domain+': glue records for nonexistent NS '+s);
    }
    for (var i = 0; i < ns.length; i++) {
	if (ns[i].substr(-domain.length) === domain) {
	    var a = d.addr[ns[i]];
	    if (!a) fail(domain+': glue records missing for NS '+ns[i]);
	    for (var j = 0; j < a.length; j++)
		nsa.push({ name: ns[i], addr: a[j] });
	} else {
	    if (d.addr[ns[i]])
		fail(domain+': spurious glue records for NS '+ns[i]);
	    nsa.push({ name: ns[i], addr: '' });
	}
    }
    if (domain.match(/\.arpa$/) && d.DS !== '') {
	// JANET's reverse DNS is currently unsigned
	info(domain+': ignoring unsupported DNSSEC records in JANET reverse DNS');
	d.DS = '';
    }
    d.NS = nsa.sort(ns_cmp);
    d.addr = undefined;
    debug('name server count '+d.NS.length);
    ns_show(debug, d.NS);
    return d;
})();

casper.start('https://domainregistry.jisc.ac.uk/dns', function started() {
    debug(this.fetchText('h1'));
});

casper.then(function login() {
    info("Loaded login page: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_Login1_UserName': creds.user,
	'#MainContent_Login1_Password': creds.pass,
    });
    this.click('#MainContent_Login1_LoginButton');
});

casper.then(function greeting() {
    var title = this.getTitle();
    info("Loaded greeting page: "+title);
    if (title !== 'Domain Registry Service')
	fail('Login failed');
    this.click('#commonActionsMenuLogin_ListPendingTickets');
});

casper.then(function view_tickets() {
    info("Loaded tickets: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_TicketTypeChoice': 'Modification'
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function count_tickets() {
    info("Loaded modification tickets: " + this.fetchText('h1'));
    var table = this.getElementsInfo('#MainContent_TicketListView tr');
    var n = table.length - 2;
    info("Pending modifications: "+n);
    if (n >= 10) {
	notice("Too many pending modifications");
	quit(1);
    }
    this.fillSelectors('form', {
	'#MainContent_TicketTypeChoice': '',
	'#MainContent_DomainFilterInput': domain
    });
    this.click('#MainContent_FilterSubmit');
});

casper.then(function find_tickets() {
    info("Loaded filtered tickets: " + this.fetchText('h1'));
    var clicky = true;
    if (this.exists('#MainContent_TicketListView_CurrentPageLabel')) {
	notice('Changes pending for ' + domain);
	if (casper.cli.options['ignore-tickets'])
	    notice('Ignoring tickets');
	else
	    clicky = false
    }
    if (clicky)
	this.click('#commonActionsMenuLogin_ListDomains');
    else
	quit(0);
});

casper.then(function choose_domain() {
    info("Loaded domain list: " + this.fetchText('h1'));
    this.fillSelectors('form', {
	'#MainContent_tbDomainNames': domain,
	'#MainContent_ShowReverseDelegatedDomains': true,
    });
    this.click('#MainContent_btnFilter');
});

casper.then(function find_domain() {
    info("Loaded filtered list: " + this.fetchText('h1'));
    for (var i = 0; ; i++) {
	var table_id = '#MainContent_DomainListView';
	var button_id = table_id+'_ViewDomainNumber'+i+'_'+i;
	var domain_sel = table_id+' > tbody '+
	    '> tr:nth-child('+(i+1)+') '+
	    '> td:nth-child(4)';
	var found = this.fetchText(domain_sel).toLowerCase();
	if (!found) {
	    debug(this.getHTML(table_id));
	    fail('Could not find domain number '+i+' searching for '+domain);
	}
	info('Found domain number '+i+' '+found);
	if (found === domain) {
	    this.click(button_id);
	    break;
	}
    }
});

casper.then(function open_domain() {
    info("Loaded domain details: " + this.fetchText('h1'));
    var id = '#MainContent_Reg';
    var wmatch = !casper.cli.options['ignore-match'];
    var fuxup = { 'Add1': 'Add',
		  'Add2': 'Add1',
		  'Add3': 'Add2',
		  'Tel': 'Phone',
		  'Postcode': 'PostCode' };
    for (var k in registrant) {
	var kk = fuxup[k] || k;
	var t = this.fetchText(id+kk);
	var arrow = ' == ';
	if (t !== registrant[k]) {
	    wmatch = false;
	    arrow = ' -> ';
	}
	info('checking '+k+' '+t+arrow+registrant[k]);
    }
    if (wmatch) {
	info('Registrant information matches for ' + domain)
    } else {
	info('Modifying registrant of ' + domain)
    }
    var tbl = this.getElementsInfo('#MainContent_nameServersTab td');
    // current name servers
    var cns = [];
    for (var j = 0, i = 0; i < tbl.length; i++) {
	var td = tbl[i].text.toLowerCase();
	if (td.match(re_ipv6) || td.match(re_ipv4)) {
	    cns[j-1].addr = td;
	} else if (td.match(re_dname)) {
	    cns[j++] = { name: td, addr: '' };
	}
    }
    cns.sort(ns_cmp);
    ns_show(debug, cns);
    var ds = '';
    if (this.exists('#MainContent_DsKeysDisplay')) {
	ds = this.getElementInfo('#MainContent_DsKeysDisplay').text;
	debug(ds);
    } else {
	debug('no DS records');
    }
    // desired name servers
    var dmatch = !casper.cli.options['ignore-match'];
    var dns = delegation.NS;
    if (cns.length !== dns.length && dns.length !== 0)
	dmatch = false;
    else
	for (var i = 0; i < dns.length; i++)
	    if (ns_cmp(cns[i], dns[i]))
		dmatch = false;
    if (ds !== delegation.DS && delegation.DS !== '')
	dmatch = false;
    if (dmatch) {
	info('Delegation information matches for ' + domain)
    } else {
	info('Modifying delegation of ' + domain)
	if (dns.length) {
	    notice('Old NS records');
	    ns_show(notice, cns);
	    notice('New NS records');
	    ns_show(notice, dns);
	}
	if (delegation.DS !== '') {
	    notice('Old DS records');
	    notice(ds);
	    notice('New DS records');
	    notice(delegation.DS);
	}
    }
    if (dmatch && wmatch) {
	notice('No need to modify ' + domain)
	quit(0);
    } else
	this.click('#MainContent_ModifyDomainButton');
});

var nsec_id = '#MainContent_Nameservers_NumberOfNonJanetSecondaries';
function get_nsec() {
    return 0^casper.getElementInfo(nsec_id + ' option[selected]').text;
}
function report_nsec() {
    var nsec = get_nsec();
    info('Number of secondaries for ' + domain + ' is ' + nsec);
    return nsec;
}

casper.then(function set_number_of_secondaries() {
    info("Loaded page: " + this.getTitle());
    var got_sec = report_nsec();
    if (delegation.NS.length > 0) {
	var want_sec = delegation.NS.length - 1;
	if (got_sec !== want_sec) {
	    debug("got "+got_sec+" want "+want_sec+" secondaries");
	    this.evaluate(function(id, val) {
		var elem = document.querySelector(id);
		elem.value = val;
		elem.onchange();
	    }, nsec_id, want_sec);
	}
    }
});

var ns_id = '#MainContent_Nameservers_';

casper.waitForSelector(delegation.NS.length < 2 ? 'html' :
       ns_id+'SecIp'+(delegation.NS.length-2),
       fill_form, // see below
function onTimeout() {
    debug(this.getHTML('#nameserversControls table'));
    fail('Timeout while adjusting nameserver form for ' + domain);
});

var modwhen_id = '#MainContent_ModificationDate_Modification';

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
    form[modwhen_id+'Time'] = tv;
    form[modwhen_id+'DateCalendar'] = d;
    notice('Modification scheduled at '+t+' '+d+' '+dd+' for '+domain);
}

var ds_id = '#MainContent_DsKeys_DsKeyTabContainer_DsPasteTab_DsKeyText';

function fill_form() {
    info("Loaded modification form: " + this.fetchText('h1'));
    var id = '#MainContent_Registrant_Reg';
    var form = {};
    for (var k in registrant)
	form[id+k] = registrant[k];
    var ns = delegation.NS;
    var n = ns.length;
    if (n > 0) {
	if (report_nsec() !== n-1)
	    fail('Unable to resize nameserver form for ' + domain);
	form[ns_id+'PrimeNameserverName'] = ns[0].name;
	form[ns_id+'PrimeNameserverIp']   = ns[0].addr;
	for (var i = 0; i < n-1; i++) {
	    form[ns_id+'SecName'+i] = ns[i+1].name;
	    form[ns_id+'SecIp'+i]   = ns[i+1].addr;
	}
    }
    if (delegation.DS !== '') {
	form[ds_id] = delegation.DS;
    }
    var now = HH_MM(new Date(Date.now() + 5 * 60 * 1000));
    var today = false;
    var times = this.getElementsInfo(modwhen_id+'Time option');
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
	quit(0);
    } else {
	this.click('#MainContent_ConfirmRequest');
    }
}

casper.waitForUrl(/ViewPendingTickets/,
function change_submitted() {
    if (this.exists('#MainContent_SubmissionText')) {
	notice(this.getElementInfo('#MainContent_SubmissionText').text);
	quit(0);
    } else {
	this.echo(this.page.plainText);
	fail('Unexpected response after submbitting modification for ' + domain);
    }
},
function onTimeout() {
    fail('Timeout after submitting modification for ' + domain);
});

casper.run();
