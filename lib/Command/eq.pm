package Command::eq;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_eq);

use Bot::Framework;
use Data::Dumper;
use Discord::Players;
use Discord::Send;
use JSON;
use Math::Trig;
use Mojo::Discord;
use POSIX qw(strftime);
use URI;
use WWW::Mechanize;

###########################################################################################
# Command eq
my $command = "eq";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^eq\s[\-0-9][0-9\.]+\s+[\-0-9][0-9\.]+\s[A-Z][a-z]+$';
my $function = \&cmd_eq;
my $usage = <<EOF;
Usage:
 `eq <lat> <lon> <state>
   .. lat = lattitude e.g. 123.4567
   .. ong = longitude e.g. -146.1234
   .. state = full state name e.g. Oklahoma
EOF

my $cachedir=$ENV{'HOME'}."/.cache/usgs.geojson";


###########################################################################################

sub new
{
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;
	 
	# Setting up this command module requires the Discord connection 
	if (defined($params{'bot'})) {
		$self->{'bot'} = $params{'bot'};
		$self->{'discord'} = $self->{'bot'}->discord;

		# Register our command with the bot
		$self->{'bot'}->add_command(
			'command'	=> $command,
			'access'	=> $access,
			'description'	=> $description,
			'usage'		=> $usage,
			'pattern'	=> $pattern,
			'function'	=> $function,
			'object'	=> $self,
		);

		$self->{send} = Discord::Send->new('bot' => $self->{bot});
		if (!defined($self->{bot}->{players})) {
			$self->{bot}->{players} = Discord::Players->new('bot' => $self->{bot});
		}
	}
	$self->{'pattern'} = $pattern;
	$self->{'command'} = $command;

	if (! -d $cachedir) {
		sytem("mkdir -p ${cachedir}");
	}
	if (defined($params{feeds})) {
		$self->{feeds} = $params{feeds};
	} else {
		$self->{feeds} = '1.0_week';
		$self->{feeds} = 'all_hour,all_day,1.0_week,1.0_month';
	}
	$self->{json} = JSON->new->allow_nonref;
	$self->{mech} =  WWW::Mechanize->new(stack_depth => 0, quiet => 0);
	
	return $self;
}

sub cmd_eq
{
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';
	my $user = $author->{username}."#".$author->{discriminator};
	#print Dumper($author);

	my $info;

	my $player = $bot->{players}->get_player($author);
	my $id = $player->get_id;

	$info = ""; # "From the stats database of ${user} we have:\n";

	my @bits;
	foreach my $m (split(/^/,$msg)) {
	@bits = split(/\s+/,$m);
	if ($bits[0] =~ /^eq$/i) {
		if ($#bits == 3) {
			$info .= sprintf("\nQuery parsed as: lat=%d, lon=%s state=%s\n", $bits[1], $bits[2], $bits[3]);
			$info .= $self->show_eq($id, @bits);
		} else {
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	

	$self->send($channel, $info);
}

sub send {
	my ($self, $channel, $info) = @_;

	my $limit = 1900; # char count, 2000 is true max but lets be safe
	my $msgcount = int(length($info)/$limit);

	my $count = 1;
	my $len=0;
	my $str="";
	foreach my $m (split(/^/,$info)) {
		my $slen = length($str);
		my $mlen = length($m);
		if ( ($slen + $mlen) > $limit) {
			$str = "```".$str;
			$str .= "[ ${count} / ${msgcount} ]";
			$str .= "```\n";
			$self->_send($channel, $str);
			$str = "";
			$count++;
			sleep(1);

			# shorten data sent for a bit
			if ($count > 2) {
				last;
			}
		}
		$str .= $m;
	}
	$str .= "[ ${count} / ${msgcount} ]\n";
	$self->_send($channel, $str);
}
sub _send {
	my ($self, $channel, $str) = @_;

	my $ret = $self->{send}->send($channel, $str);
	print STDERR Dumper($ret);
}

sub show_eq {
	my ($self, $player_id, $tmp, $lat, $lon, $state) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};
	my $ret = "";

	my $stats = sprintf("pid=%s, tmp=%s, lat=%s, lon=%s, state=%s\n",
		$player_id, $tmp, $lat, $lon, $state);
	$self->{send}->send($channel, $stats);

	foreach my $f (split(/,/,$self->{feeds})) {
		my $content = $self->getfeed($f);
		my $info = $self->{json}->decode($content);
		if (!defined($info)) {
			print STDERR "No eq info retrieved..\n";
			next;
		}
		my $coll = $info->{features};
		if (!defined($coll)) {
			print STDERR "No Collection retrieved..\n";
			next;
		}
		foreach my $eq (@{$coll}) {
			my $time = $eq->{properties}->{time};
			$time *= .001;
			my $times = strftime "%s", localtime($time);
			$eq->{properties}->{times} = $times;
			$self->{eq}->{$eq->{id}}=$eq;
		}
	}

	foreach my $eqid (sort {
		$self->{eq}->{$b}->{properties}->{times}
			cmp
		$self->{eq}->{$a}->{properties}->{times}
	    } keys %{$self->{eq}}) {
		my $eq = $self->{eq}->{$eqid};
		my $place = $eq->{properties}->{place};
		if (defined($state)) {
			if (! ($place =~ /$state/)) {
				next;
			}
		}
		if (!defined($place)) {
			next;
		}
		my $mag = $eq->{properties}->{mag};
		my $time = $eq->{properties}->{time};
		$time *= .001;
		$time = strftime "%a %b %e %H:%M:%S %Y", localtime($time);

		my $geom = $eq->{geometry}->{coordinates};
		my ($eqlon,$eqlat,$eqdepth) = @{$geom};


		my $distance = sprintf "%0.2fmi", $self->distance($lat, $lon, $eqlat, $eqlon);
		$place =~ m/^(.*[[:space:]]*)([0-9]+)km(.*)$/;
		my ($plpre,$plkm,$plpost) = ($1,$2,$3);
		if (defined($plkm)) {
			if (!defined($plpre)) {
				$plpre="";
			}
			my $plmi = $plkm * 0.63;
			$place = sprintf "%6.2fmi%s", $plpre.$plmi, $plpost;
		}

		my $id = $eq->{id};
	
		$ret .= sprintf("%s|%12s|%4.1f|%9s|%s\n",
		    $time, $id, $mag, $distance, $place);
	}
	printf STDERR "show_eq returning %d chars\n", length($ret);
	return $ret;
}

sub
distance
{
	my ($self,$lat1, $long1, $lat2, $long2, $unit) = @_;
	my $theta = $long1 - $long2;
	my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
	$dist = acos($dist);
	$dist = rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
	if (!defined($unit)) {
		$unit = "";
	}
	if ($unit eq "K") {
		$dist = $dist * 1.609344;
	} elsif ($unit eq "N") {
		$dist = $dist * 0.8684;
	}
	return ($dist);
}
sub getfeed {
	my ($self,$f) = @_;
	my $cachefile = $cachedir."/".$f;

	my $uri;
	my $content = "";
	if (-f $cachefile) {
		# if $cachefile is newer than 5mins ago
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                   $atime,$mtime,$ctime,$blksize,$blocks) = stat($cachefile);
		if ($mtime > (time()-5*60)) {
			open(CF,$cachefile);
			while (<CF>) {
				$content .= $_;
			}
			close(CF);
			return $content;
		}
	}

	$uri = URI->new("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/${f}.geojson");

	my $req = HTTP::Request->new( 'GET', $uri );

	eval {
		$self->{mech}->request($req);
	};
	if ($@) {
		printf STDERR "request failure: %s\n", $@;
		next;
	}
	$content = $self->{mech}->content();
	open(CF, ">", $cachefile);
	print CF $content;
	close(CF);
	return $content;
}

1;

