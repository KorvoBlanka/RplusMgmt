package RplusMgmt::Controller::Events;

use Mojo::Base 'Mojolicious::Controller';

my @subscribers;

sub subscribe_on_realty_events {
    my $cb = shift;
    
    push @subscribers, $cb;
    
    return $cb;
}

sub unsubscribe {
    my $cb = shift;
    @subscribers = grep { $_ != $cb } @subscribers;
}

sub realty_event {
    my $arg = shift;
    $_->($arg) for @subscribers;
}

1;
