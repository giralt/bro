##! Activates port-independent protocol detection and selectively disables
##! analyzers if protocol violations occur.

@load frameworks/signatures

module DPD;

## Add the DPD signatures to the signature framework.
redef signature_files += "frameworks/dpd/base/dpd.sig";

export {
	redef enum Log::ID += { DPD };

	type Info: record {
		## Timestamp for when protocol analysis failed.
		ts:             time            &log;
		## Connection unique ID.
		uid:            string          &log;
		## Connection ID.
		id:             conn_id         &log;
		## Transport protocol for the violation.
		proto:          transport_proto &log;
		## The analyzer that generated the violation.
		analyzer:       string          &log;
		## The textual reason for the analysis failure.
		failure_reason: string          &log;
		
		## Disabled analyzer IDs.  This is only for internal tracking 
		## so as to not attempt to disable analyzers multiple times.
		# TODO: This is waiting on ticket #460 to remove the '0'.
		disabled_aids:  set[count]      &default=set(0);
	};
	
	## Ignore violations which go this many bytes into the connection.
	## Set to 0 to never ignore protocol violations.
	const ignore_violations_after = 10 * 1024 &redef;
}

redef record connection += {
	dpd: Info &optional;
};

event bro_init()
	{
	Log::create_stream(DPD, [$columns=Info]);
	
	# Populate the internal DPD analysis variable.
	for ( a in dpd_config )
		{
		for ( p in dpd_config[a]$ports )
			{
			if ( p !in dpd_analyzer_ports )
				dpd_analyzer_ports[p] = set();
			add dpd_analyzer_ports[p][a];
			}
		}
	}

event protocol_confirmation(c: connection, atype: count, aid: count) &priority=10
	{
	local analyzer = analyzer_name(atype);
	
	if ( fmt("-%s",analyzer) in c$service )
		delete c$service[fmt("-%s", analyzer)];

	add c$service[analyzer];
	}

event protocol_violation(c: connection, atype: count, aid: count,
                         reason: string) &priority=10
	{
	local analyzer = analyzer_name(atype);
	# If the service hasn't been confirmed yet, don't generate a log message
	# for the protocol violation.
	if ( analyzer !in c$service )
		return;
		
	delete c$service[analyzer];
	add c$service[fmt("-%s", analyzer)];
	
	local info: Info;
	info$ts=network_time();
	info$uid=c$uid;
	info$id=c$id;
	info$proto=get_conn_transport_proto(c$id);
	info$analyzer=analyzer;
	info$failure_reason=reason;
	c$dpd = info;
	}

event protocol_violation(c: connection, atype: count, aid: count, reason: string) &priority=5
	{
	if ( !c?$dpd || aid in c$dpd$disabled_aids )
		return;

	local size = c$orig$size + c$resp$size;
	if ( ignore_violations_after > 0 && size > ignore_violations_after )
		return;
	
	# Disable the analyzer that raised the last core-generated event.
	disable_analyzer(c$id, aid);
	add c$dpd$disabled_aids[aid];
	}

event protocol_violation(c: connection, atype: count, aid: count,
				reason: string) &priority=-5
	{
	if ( c?$dpd )
		Log::write(DPD, c$dpd);
	}