# Copyright (C) 2017 University Of Michigan
# 
# This file is part of gta-postprocessing.
# 
# gta-postprocessing is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# gta-postprocessing is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with gta-postprocessing.  If not, see <http://www.gnu.org/licenses/>.
# 


from argparse import ArgumentParser
import postgresql as pg
import xml.etree.ElementTree as ET
from progressbar import ProgressBar
from os.path import join
from os import link
from pathlib import Path
from itertools import groupby
from xml.dom import minidom
from typing import List, Tuple
import numpy as np
from PIL import Image
from os import link
from configparser import ConfigParser
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor
from threading import Semaphore
CONFIG = ConfigParser()
CONFIG.read("gta-postprocessing.ini")
def process(file, detections, output_dir):
    np_file = np.load(str(file))
    output_path = output_dir / (file.stem + ".png")
    if output_path.exists() and not args.replace: return
    if not 'arr_0' in np_file: return
    raw_segs = np_file['arr_0']
    new_segs = np.zeros((*raw_segs.shape, 3), dtype=np.uint8)
    i = 0
    for val in [x['handle'] for x in detections]:
        new_segs[raw_segs == val] = colors[i % len(colors)]
        i += 1
    """
    for val in np.unique(raw_segs):
        if val == 0: continue
        new_segs[raw_segs == val] = colors[i % len(colors)]
        i += 1
    """
    img = Image.fromarray(new_segs)
    img.save(str(output_path))

def gen_annotation(outputDir: str, detections, width, height):

    root = ET.Element('annotation')
    folder = ET.SubElement(root, 'folder')
    folder.text = outputDir

    ET.SubElement(root, 'filename').text = \
        join(str(detections[0]['runguid']), detections[0]['imagepath'])
    source = ET.SubElement(root, 'source')
    ET.SubElement(source, 'database').text = "NGV Postgres sim_annotations"
    ET.SubElement(source, 'annotation').text = "Grand Theft Auto V"
    ET.SubElement(source, 'image').text = "Grand Theft Auto V"
    size = ET.SubElement(root, 'size')
    ET.SubElement(size, 'width').text = str(width)
    ET.SubElement(size, 'height').text = str(height)
    ET.SubElement(size, 'depth').text = "3"
    ET.SubElement(root, 'segmented').text = "1"


    for detection in detections:
        if detection['coverage'] is None: continue
        object = ET.SubElement(root, 'object')
        box = detection['best_bbox']
        if box is None: continue
        xmin = box.low.x * width
        xmax = box.high.x * width
        ymin = box.low.y * height
        ymax = box.high.y * height

        if str(detection['class']) == 'Motorcycles':
            ET.SubElement(object, 'name').text = 'motorbike'
        else:
            ET.SubElement(object, 'name').text = str(detection['type'])
        # TODO: get this right when we include truncated objects
        ET.SubElement(object, 'truncated').text = "0"
        ET.SubElement(object, 'occluded').text = str(1 - detection['coverage'])
        ET.SubElement(object, 'pose').text = 'Unspecified'
        ET.SubElement(object, 'difficult').text = "0"
        bbox = ET.SubElement(object, 'bndbox')
        ET.SubElement(bbox, 'xmin').text = str(int(xmin) + 1)
        ET.SubElement(bbox, 'ymin').text = str(int(ymin) + 1)
        ET.SubElement(bbox, 'xmax').text = str(int(xmax) + 1)
        ET.SubElement(bbox, 'ymax').text = str(int(ymax) + 1)
        ET.SubElement(object, "handle").text = str(detection['handle'])
    return root


def gen_image_set(outputdir: Path, snapshot_ids):
    image_set_dir = outputdir / "ImageSets" / "Main"
    image_set_dir.mkdir(parents=True)
    image_set_file = image_set_dir / "trainval.txt"
    image_set_file.write_text("\n".join([str(x) for x in snapshot_ids]))

def gen_annotations(imagedir, outputdir: Path, detections):
    (outputdir / "Annotations").mkdir(exist_ok=True)
    detections_list = []
    for s, ds in groupby(detections, key=lambda x: x['snapshot_id']):
        detections_list.append((s, list(ds)))
    bar = ProgressBar()
    for s, ds in bar(detections_list):
        image_path = Path(imagedir) / str(ds[0]['runguid']) / str(ds[0]['imagepath'])
        if not image_path.exists():
            continue
        annotation = gen_annotation(str(outputdir), ds, ds[0]['width'], ds[0]['height'])
        with open(outputdir / "Annotations" / (str(s) + ".xml"), 'w') as f:
            xmlstr = ET.tostring(annotation, encoding='utf-8')
            xml = minidom.parseString(xmlstr)
            f.write(xml.toprettyxml())
    gen_image_set(outputdir, list(zip(*detections_list))[0])

def save_image(source, dst):
    with Image.open(str(source), 'r') as img:
        img.save(str(dst))

def link_pngs(output_dir: Path, pixelpath: Path, detections):
    (output_dir / "SegmentationObject").mkdir(exist_ok=True)
    exec = ThreadPoolExecutor(25)
    sem = Semaphore(25)
    for s, ds in tqdm(groupby(detections, key=lambda x: x['snapshot_id'])):
        sem.acquire()
        f = exec.submit(process, pixelpath / ( str(s) + ".npz"), list(ds), output_dir / "SegmentationObject")
        f.add_done_callback(lambda x: sem.release())
    exec.shutdown(wait=True)


def link_images(image_dir: Path, output_dir: Path, detections):
    output_path = output_dir / "JPEGImages"
    output_path.mkdir(exist_ok=True)
    pool = ThreadPoolExecutor(10)
    bar = ProgressBar()
    for s, ds in bar(groupby(detections, key=lambda x: x['snapshot_id'])):
        ds = list(ds)[0]
        image_path = output_path / (str(s) + ".jpg")
        if image_path.exists(): continue
        source_path = image_dir / str(ds['runguid']) / str(ds['imagepath'])
        if source_path.exists():
            pool.submit(save_image, source_path, image_path)
    pool.shutdown(wait=True)

def hardlink_images(search_dir: Path, output_dir: Path, detections):
    output_path = output_dir / "JPEGImages"
    output_path.mkdir(exist_ok=True)
    bar = ProgressBar()
    for s, ds in bar(groupby(detections, key = lambda x: x['snapshot_id'])):
        ds = list(ds)[0]
        image_path = output_path / (str(s) + ".jpg")
        if image_path.exists(): continue
        source_path = search_dir / (str(s) + ".jpg")
        link(source_path, image_path)

def main(query, image_dir, outputdir: Path, hardlink: Path, pixel_path: Path):
    conn = pg.open(CONFIG["Database"]["URI"])
    print("Query: %s" % (query, ))
    outputdir.mkdir(parents=True, exist_ok=True)
    detections = conn.query(query)
    for run, detections in groupby(detections, lambda x: str(x['runguid'])):
        detections = list(detections)
        (outputdir / run).mkdir(exist_ok=True)
        print(outputdir/run)
        gen_annotations(image_dir, outputdir/run, detections)
        if hardlink is None:
            link_images(image_dir, outputdir/run, detections)
        else:
            hardlink_images(hardlink, outputdir/run, detections)
        link_pngs(outputdir/run, pixel_path, detections)

# ---------------------------- PROGRAM SETUP ----------------------------------
if __name__ == "__main__":
    parser = ArgumentParser(description="Generate pascal VOC annotations from NGV database")
    parser.add_argument('--query', dest='query', required=True, type=str,
                        help="Query to execute, should return list of detections")
    parser.add_argument('--out', dest='out', required=True, type=Path,
                        help="Output Directory")
    parser.add_argument('--image_path', dest='image_path', type=Path, required=True, help="Path to the GTA image files")
    #hardlinks = parser.add_mutually_exclusive_group(required=False)
    #hardlinks.add_argument('--hardlink', dest='hardlink', action='store_true')
    #hardlinks.add_argument('--no-hardlink', dest='hardlink', action='store_false')
    parser.add_argument('--link_path', dest='link_path', required=False, type=Path, default=None)
    parser.add_argument('--pixel_path', dest='pixel_path', required=False, type=Path)

    args = parser.parse_args()
    main(args.query, args.image_path, args.out, args.link_path, args.pixel_path)

