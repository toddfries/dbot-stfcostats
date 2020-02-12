package Command::FAQ;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_faq);

use Bot::Framework;
use Data::Dumper;
use Discord::Players;
use Discord::Send;
use Mojo::Discord;

###########################################################################################
# Command FAQ
my $command = "stats faq";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^stats faq$';
my $function = \&cmd_faq;
my $usage = <<EOF;
stats faq
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
        'command'       => $command,
        'access'        => $access,
        'description'   => $description,
        'usage'         => $usage,
        'pattern'       => $pattern,
        'function'      => $function,
        'object'        => $self,
    );

    $self->{send} = Discord::Send->new('bot' => $self->{bot});
    if (!defined($self->{bot}->{players})) {
	$self->{bot}->{players} = Discord::Players->new('bot' => $self->{bot});
    }
    
    return $self;
}

sub cmd_faq
{
    my ($self, $channel, $author) = @_;

    my $discord = $self->{'discord'};
    my $bot = $self->{'bot'};
    my $file = $self->{'bot'}->{'faqfile'};

    if ($bot->{debug} > 0) {
	print "Arrived at cmd_faq\n";
    }

    my $player = $bot->{players}->get_player($author);
    my $id = $player->get_id;

    my $faq = "The F.A.Q.!\n";
    if (-f $file) {
	open(F,$file);
	while(<F>) {
		$faq .= $_;
	}
	close(F);
    }

    if ($bot->{debug} > 0) {
	printf "Sending a %d faq back\n", length($faq);
    }
    
    # We can use some special formatting with the webhook.
    if ( my $hook = $bot->has_webhook($channel) )
    {
        $discord->send_webhook($channel, $hook, $faq);
    }
    else
    {
        $discord->send_message($channel, $faq);
    }
}

1;
