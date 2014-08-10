package Rplus::Model::DictApScheme::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictApScheme;

sub object_class { 'Rplus::Model::DictApScheme' }

__PACKAGE__->make_manager_methods('dict_ap_schemes');

1;

