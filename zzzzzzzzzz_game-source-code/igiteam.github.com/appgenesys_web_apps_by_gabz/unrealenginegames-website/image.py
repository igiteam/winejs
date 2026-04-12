import json

def add_image_property(input_file, output_file, image_url):
    """
    Reads a JSON array from input_file, adds an 'image' property to each object, and saves it to output_file.
    :param input_file: Path to the input JSON file.
    :param output_file: Path to save the modified JSON file.
    :param image_url: The URL or image placeholder to be added.
    """
    try:
        with open(input_file, 'r', encoding='utf-8') as file:
            data = json.load(file)
        
        if not isinstance(data, list):
            raise ValueError("JSON data is not an array")
        
        for i in range(len(data)):
            if isinstance(data[i], dict):
                data[i] = {"image": image_url, **data[i]}
            else:
                raise ValueError("Each element in JSON array must be an object")
        
        with open(output_file, 'w', encoding='utf-8') as file:
            json.dump(data, file, indent=4)
        
        print(f"Modified JSON saved to {output_file}")
    except Exception as e:
        print(f"Error: {e}")


def main():
    input_file = "umodel_compatibility.json"
    output_file = "umodel_compatibility_.json"
    image_url = "https://i.ibb.co/pvHz3Zb1/xbox360.png"
    add_image_property(input_file, output_file, image_url)

if __name__ == "__main__":
    main()

