package Rplus::DB::Object::Metadata::Column::Geography;

use Rplus::Modern;

use base qw(Rose::DB::Object::Metadata::Column::Varchar);

our $VERSION = '0.01';

__PACKAGE__->delete_common_method_maker_argument_names(qw(length));

sub type { 'geography' }

sub should_inline_value {
    my ($self, $db, $value) = @_;
    return $value ? 1 : 0;
}

sub perl_column_definition_attributes {
    grep { $_ ne 'length' } shift->SUPER::perl_column_definition_attributes;
}

1;
