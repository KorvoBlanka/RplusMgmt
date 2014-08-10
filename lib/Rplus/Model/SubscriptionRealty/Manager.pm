package Rplus::Model::SubscriptionRealty::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::SubscriptionRealty;

sub object_class { 'Rplus::Model::SubscriptionRealty' }

__PACKAGE__->make_manager_methods('subscription_realty');

1;

