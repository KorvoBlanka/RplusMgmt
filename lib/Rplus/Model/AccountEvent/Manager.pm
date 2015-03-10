package Rplus::Model::AccountEvent::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::AccountEvent;

sub object_class { 'Rplus::Model::AccountEvent' }

__PACKAGE__->make_manager_methods('account_events');

1;

