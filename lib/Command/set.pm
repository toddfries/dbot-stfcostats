package Command::set;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_q);

use Bot::Framework;
use Data::Dumper;
use Discord::Players;
use Discord::Send;
use Mojo::Discord;

###########################################################################################
# Command q
my $command = "set";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^(stats[ .]([a-z]+|[a-z]+\s[^\s]+)|stats)$';
my $function = \&cmd_set;
my $usage = <<EOF;
Usage:
 `stats.<var> [<val>]`
   .. var = [ academy | adv_training | attack_training | defense_training ]
   .. val = number, it not present, consider it a query to retrieve and display
 -or-
 `stats`
   .. 
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
	$self->{'command'} = $command;

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
	
	return $self;
}

sub cmd_set
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

	$info = "From the stats database of ${user} we have:\n";

	my @bits;
	foreach my $m (split(/^/,$msg)) {
	$m =~ s/stats\./stats /;
	@bits = split(/\s+/,$m);
	if ($bits[0] =~ /^stats$/i) {
		if ($#bits == 2) {
			#$info .= sprintf("\nset stats.%s to %d\n", $bits[1], $bits[2]);
			$info .= $self->set($id, $bits[1], $bits[2]);
		} elsif ($#bits == 1) {
			#$info .= sprintf("\nget stats.%s\n", $bits[1]);
			$info .= $self->get($id, $bits[1]);
		} elsif ($#bits == 0) {
			$info .= $self->getall($id);
		} else {
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	

	$self->{send}->send($channel, $info);
}

sub getall {
	my ($self, $id) = @_;
	my $info = "";
	foreach my $v (('academy', 'adv_train', 'attack_train', 'defense_train')) {
		$info .= $self->get($id, $v)."\n";
	}
	return $info;
}
		

sub get {
	my ($self, $id, $var) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $q = "select ps.${var} from player_stats as ps, players as p where ps.player_id = p.id";
	$q   .= " and p.id = ${id}";
	my $val = $db->do_oneret_query($q);
	if (!defined($val) || $val == -1) {
		$self->set($id, $var, 0);
		$val = 0;
	}
	return "stats.${var} = $val";

}
sub set {
	my ($self, $id, $var, $val) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $q = "select ps.id, ps.${var} from player_stats as ps, players as p where ps.player_id = p.id";
	$q .= " and p.id = ${id}";
	my $sth = $db->doquery($q);
	my $rv = $sth->rows;
	my ($rid, $oval);
	if ($rv > 0) {
		($rid, $oval) = $sth->fetchrow_array;
	}

	
	if (defined($oval)) {
		$q = "update player_stats set ${var} = ${val} where id = ${rid}";
		$db->doquery($q);
		return "stats.${var} = $oval -> $val";
	}
	$q = "insert into player_stats ( player_id, ${var} ) values ( ${id}, ${val} )";
	$db->doquery($q);
	return "stats.${var} = $val";
}

1;
