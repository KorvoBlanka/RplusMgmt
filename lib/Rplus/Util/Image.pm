package Rplus::Util::Image;

use Rplus::Modern;

use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use Rplus::Util::Config;

use Time::HiRes;
use File::Path qw(make_path);
use Image::Magick;

sub load_image {
    my ($realty_id, $file, $storage_path, $crop) = @_;

    my $path = $storage_path.'/photos/'.$realty_id;
    my $name = Time::HiRes::time =~ s/\.//r; # Unique name

    my $photo = Rplus::Model::Photo->new;

    make_path($path);
    $file->move_to($path.'/'.$name.'.jpg');

    # Convert image to jpeg
    my $image = Image::Magick->new;
    $image->Read($path.'/'.$name.'.jpg');
    if ($crop != 0 && $crop < $image->Get('height')) {
        $image->Crop(geometry => '-0'.$crop);
    }
    if ($image->Get('width') > 1920 || $image->Get('height') > 1080 || $image->Get('mime') ne 'image/jpeg') {
        $image->Resize(geometry => '1920x1080');
        $image->Write($path.'/'.$name.'.jpg');
    }
    $image->Resize(geometry => '320x240');
    $image->Extent(geometry => '320x240', gravity => 'Center', background => 'white');
    $image->Thumbnail(geometry => '320x240');
    $image->Write($path.'/'.$name.'_thumbnail.jpg');

    # Save
    $photo->realty_id($realty_id);
    $photo->filename($name.'.jpg');
    $photo->thumbnail_filename($name.'_thumbnail.jpg');

    $photo->save;

    # Update realty change_date
    Rplus::Model::Realty::Manager->update_objects(
        set => {change_date => \'now()'},
        where => [id => $realty_id],
    );
}

1;
