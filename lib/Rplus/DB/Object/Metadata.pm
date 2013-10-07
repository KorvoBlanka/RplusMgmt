package Rplus::DB::Object::Metadata;

use Rplus::Modern;

use base qw(Rose::DB::Object::Metadata);

__PACKAGE__->column_type_class('geometry'          => 'Rplus::DB::Object::Metadata::Column::Geometry');
__PACKAGE__->column_type_class('postgis.geometry'  => 'Rplus::DB::Object::Metadata::Column::Geometry');
__PACKAGE__->column_type_class('geography'         => 'Rplus::DB::Object::Metadata::Column::Geography');
__PACKAGE__->column_type_class('postgis.geography' => 'Rplus::DB::Object::Metadata::Column::Geography');

1;
