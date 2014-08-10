package Rplus::Model::RealtyOfferType::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RealtyOfferType;

sub object_class { 'Rplus::Model::RealtyOfferType' }

__PACKAGE__->make_manager_methods('realty_offer_types');

1;

