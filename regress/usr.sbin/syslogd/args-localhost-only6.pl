# The client writes a message to Sys::Syslog native method.
# The syslogd writes it into a file and through a pipe.
# The syslogd -6 passes it via IPv6 UDP to localhost.
# The server receives the message on its UDP socket.
# Check that localhost gets resolved to the ::1 address.

use strict;
use warnings;
use Socket;

our %args = (
    syslogd => {
	loghost => '@localhost:$connectport',
	options => ["-6"],
    },
    server => {
	listen => { domain => AF_INET6, addr => "::1" },
    },
);

1;
