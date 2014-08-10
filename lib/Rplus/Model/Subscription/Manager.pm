package Rplus::Model::Subscription::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Subscription;

sub object_class { 'Rplus::Model::Subscription' }

__PACKAGE__->make_manager_methods('subscriptions');

1;

