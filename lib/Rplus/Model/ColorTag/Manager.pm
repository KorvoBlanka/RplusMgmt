package Rplus::Model::ColorTag::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::ColorTag;

sub object_class { 'Rplus::Model::ColorTag' }

__PACKAGE__->make_manager_methods('color_tags');

1;

