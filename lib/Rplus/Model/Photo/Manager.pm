package Rplus::Model::Photo::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Photo;

sub object_class { 'Rplus::Model::Photo' }

__PACKAGE__->make_manager_methods('photos');

1;

