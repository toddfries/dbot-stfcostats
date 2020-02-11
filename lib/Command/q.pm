package Command::q;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_q);

use Mojo::Discord;
use Bot::Framework;
use Data::Dumper;

###########################################################################################
# Command q
my $command = "q";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^q\s([a-z]+\s[0-9]+\s[a-z]+[a-z\+]+|[a-z][a-z\+0-9]+)$';
my $function = \&cmd_q;
my $usage = <<EOF;
Usage:
 `q <command> <count> <algo>`
   .. command = top
   .. algo = attack, health, defense, combo
   -or-
 `q <shortname>`
EOF
###########################################################################################

sub new
{
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;
	 
	# Setting up this command module requires the Discord connection 
	$self->{'bot'} = $params{'bot'};
	$self->{'discord'} = $self->{'bot'}->discord;
	$self->{'pattern'} = $pattern;

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
	
	return $self;
}

sub cmd_q
{
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';

	my $info;

	my $q = "select id from players where did='".$author->{id}."'";

	my $id = $bot->{'db'}->do_oneret_query($q);
	if (defined($id) && $id > -1) {
		#$info = "Your id in my db is ${id}, did ".$author->{id};
	} else {
		$q = "INSERT INTO players ( did ) values ( '".$author->{id}."')";
		my $oid = $bot->{'db'}->do_oid_insert($q, 'o::cmd_q');
		$q = "SELECT id FROM players where oid = ${oid}";
		$id = $bot->{db}->do_oneret_query($q);
		#$info = "Added your id in my db, it is ${id}, did ".$author->{id};
	}

	my @bits;
	foreach my $m (split(/^/,$msg)) {
	@bits = split(/\s+/,$m);
	if ($bits[0] eq "q") {
		if ($#bits == 3) {
			$info .= sprintf("\nQuery parsed as: cmd='%s', count=%d, op=%s\n", $bits[1], $bits[2], $bits[3]);
			$info .= $self->query($id, @bits);
		} elsif ($#bits == 1) {
			$info .= sprintf("\nQuery parsed as: officer='%s'\n", $bits[1]);
			$info .= $self->show_stats($id, @bits);
		} else {
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	
	# We can use some special formatting with the webhook.
	if ( my $hook = $bot->has_webhook($channel) )
	{
		$discord->send_webhook($channel, $hook, $info);
	} else {
		$discord->send_message($channel, $info);
	}
}

sub query {
	my ($self, $player_id, $qcmd, $cmd, $count, $op) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my ($sort);

	# q top 5 strength	
	if ($cmd eq "top") {
		$sort = "desc";
	} else {
		$sort = "asc";
	}
	my $order = "order by ";

	print "op: $op\n";
	my ($attack,$defense,$health) = (0,0,0);
	if ($op =~ /attack/) {
		$attack = 1;
	}
	if ($op =~ /defense/) {
		$defense = 1;
	}
	if ($op =~ /health/) {
		$health = 1;
	}

	my $counter = 0;
	if ($health > 0 && $defense > 0) {
		$order .= " (s.defense + s.health) ";
		$counter++;
		$health = 0;
		$defense = 0;
	}
	if ($health > 0 && $attack > 0) {
		$order .= " (s.attack + s.health) ";
		$counter++;
		$health = 0;
		$attack = 0;
	}
	if ($defense > 0 && $attack > 0) {
		$order .= " (s.attack + s.defense) ";
		$counter++;
		$defense = 0;
		$attack = 0;
	}
	if ($health > 0) {
		$order .= "s.health ";
		$counter++;
	}
	if ($defense > 0) {
		if ($counter++ > 0) {
			$order .= ",";
		}
		$order .= "s.defense ";
	}
	if ($attack > 0) {
		if ($counter++ > 0) {
			$order .= ",";
		}
		$order .= "s.attack ";
	}
	
	my $qlim = " where s.player_id = $player_id and s.officer_id = o.id ";
	$qlim .= " $order $sort ";
	$qlim .= " limit ${count}";

	$self->_stats_fmt($qlim);
}

sub show_stats {
	my ($self, $player_id, $tmp, $short) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $qlim = " where s.player_id = $player_id and s.officer_id = o.id ";
	$qlim .= " and o.short = ".$db->quote($short);

	$self->_stats_fmt($qlim);
}

sub _stats_fmt {
	my ($self, $qlim) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $q = "select o.short, s.rank, s.level, s.attack, s.defense, s.health ";
	$q .= "from officers as o, ostats as s ";

	$q .= $qlim;


	print "q: ${q}\n";

	my $sth = $db->doquery($q);
	my $rv = $sth->rows;

	if ($rv < 1) {
		return "0 info returned\n";
	}

	my ($short, $rank, $level);
	my $i = 0;
	my $str = sprintf "`    %15s%3s%3s%4s%4s%4s`\n",
		"Short","R","L","Att","Def","Hea";
			
	my ($attack, $defense, $health);
	while (($short, $rank, $level, $attack, $defense, $health) = $sth->fetchrow_array) {
		$i++;
		$str .= sprintf "`%2d. %15s %2d %2d %3d %3d %3d`\n", 
			$i, $short, $rank, $level, $attack, $defense, $health;
	}
	return $str;
}

1;
