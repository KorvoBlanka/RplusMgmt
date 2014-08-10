package Rplus::Model::Media::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Media;

sub object_class { 'Rplus::Model::Media' }

__PACKAGE__->make_manager_methods('media');

1;

