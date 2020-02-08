package Command::FAQ;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_faq);

use Mojo::Discord;
use Bot::Framework;
use Data::Dumper;

###########################################################################################
# Command FAQ
my $command = "FAQ";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^stats faq';
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
    
    return $self;
}

sub cmd_faq
{
    my ($self, $channel, $author) = @_;

    my $discord = $self->{'discord'};
    my $bot = $self->{'bot'};
    my $file = $self->{'bot'}->{'faqfile'};

    my $faq;
    if (-f $file) {
	open(F,$file);
	$faq = "";
	while(<F>) {
		$faq .= $_;
	}
	close(F);
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
