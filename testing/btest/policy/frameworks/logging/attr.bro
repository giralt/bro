# @TEST-USE-PROFILES dataseries
# @TEST-EXEC: bro %INPUT
# @TEST-EXEC: btest-diff ssh.log

module SSH;

export {
	redef enum Log::ID += { SSH };

	type Log: record {
		t: time;
		id: conn_id;
		status: string &optional &log;
		country: string &default="unknown" &log;
	};
}

event bro_init()
{
	Log::create_stream(SSH, [$columns=Log]);

    local cid = [$orig_h=1.2.3.4, $orig_p=1234/tcp, $resp_h=2.3.4.5, $resp_p=80/tcp];

	Log::write(SSH, [$t=network_time(), $id=cid, $status="success"]);
	Log::write(SSH, [$t=network_time(), $id=cid, $status="failure", $country="US"]);
	Log::write(SSH, [$t=network_time(), $id=cid, $status="failure", $country="UK"]);
	Log::write(SSH, [$t=network_time(), $id=cid, $status="success", $country="BR"]);
	Log::write(SSH, [$t=network_time(), $id=cid, $status="failure", $country="MX"]);
	
}
