import sys
import cv
import cv2
import tesseract

filename = sys.argv[1]
tmpfilename = sys.argv[2]
mode = sys.argv[3]
img = cv2.imread(filename, cv2.IMREAD_UNCHANGED)

h,w,cc = img.shape

# avito hack
if (cc == 4 and mode == 'avito'):
	for x in range(0, w):
		for y in range(0, h):
			r,g,b,a = img[y, x]
			v = 255 - a;
			img[y, x] = [v, v, v, 255]

img = cv2.resize(img, (0,0), fx = 8.0, fy = 8.0)
cv2.imwrite(tmpfilename, img)

img = cv.LoadImage(tmpfilename, cv.CV_LOAD_IMAGE_GRAYSCALE)
api = tesseract.TessBaseAPI()
api.Init(".", "rus", tesseract.OEM_DEFAULT)
#api.SetPageSegMode(tesseract.PSM_SINGLE_WORD)
api.SetPageSegMode(tesseract.PSM_AUTO)
tesseract.SetCvImage(img, api)
text = api.GetUTF8Text()
conf = api.MeanTextConf()
print text
api.End()
