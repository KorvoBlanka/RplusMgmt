package Rplus::Model::DictBalcony::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictBalcony;

sub object_class { 'Rplus::Model::DictBalcony' }

__PACKAGE__->make_manager_methods('dict_balconies');

1;

