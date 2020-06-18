//
//  VIMCategory+Tests.swift
//  VimeoNetworkingExample-iOSTests, VimeoNetworkingExample-tvOSTests
//
//  Created by Westendorf, Mike on 5/21/17.
//  Copyright © 2016 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import XCTest
@testable import VimeoNetworking

class VIMCategory_Tests: XCTestCase
{
    private var parsedCategory: VIMCategory?
    private var categoryJSONDict: VimeoClient.ResponseDictionary?
    
    override func setUp()
    {
        super.setUp()
        
        guard let categoryJSONDict = ResponseUtilities.loadResponse(from: "categories-animation-response.json") else
        {
            self.parsedCategory = nil
            self.categoryJSONDict = nil
            return
        }
        
        self.categoryJSONDict = categoryJSONDict
        self.parsedCategory = try! VIMObjectMapper.mapObject(responseDictionary: categoryJSONDict) as VIMCategory
    }
    
    func test_VIMCategory_ValidateParsing()
    {
        XCTAssertNotNil(self.parsedCategory)
        
        XCTAssertEqual(self.parsedCategory?.name, self.categoryJSONDict?["name"] as? String)
        XCTAssertEqual(self.parsedCategory?.uri, self.categoryJSONDict?["uri"] as? String)
        XCTAssertEqual(self.parsedCategory?.link, self.categoryJSONDict?["link"] as? String)
        XCTAssertTrue(self.parsedCategory?.isTopLevel ?? false)

        //There is no modifiedTime field in the response data so this should be nil
        XCTAssertNil(self.parsedCategory?.modifiedTime)
        
        XCTAssertNotNil(self.parsedCategory?.pictureCollection)
        XCTAssertGreaterThan(self.parsedCategory?.pictureCollection?.pictures?.count ?? 0, 0)
        
        XCTAssertNotNil(self.parsedCategory?.subcategories)
        XCTAssertGreaterThan(self.parsedCategory?.subcategories?.count ?? 0, 0)
    }
    
    func test_VIMCategory_IsFollowingReturnsTrue()
    {
        XCTAssertNotNil(self.parsedCategory)
        XCTAssertTrue(self.parsedCategory?.isFollowing() ?? false)
    }
    
    func test_VIMCategory_ParsedSubcategories()
    {
        XCTAssertNotNil(self.parsedCategory?.subcategories)
        
        let subCategories = self.categoryJSONDict?["subcategories"] as? [Dictionary<String, String>]
        
        var i = 0
        for subCategory in self.parsedCategory?.subcategories as! [VIMCategory]
        {
            XCTAssertNotNil(subCategory.name)
            XCTAssertNotNil(subCategory.uri)
            XCTAssertNotNil(subCategory.link)
            
            XCTAssertEqual(subCategory.name, subCategories?[i]["name"])
            XCTAssertEqual(subCategory.uri, subCategories?[i]["uri"])
            XCTAssertEqual(subCategory.link, subCategories?[i]["link"])
            
            i = i + 1
        }
    }

    func test_VIMCategory_ParsedPictureCollection()
    {
        XCTAssertNotNil(self.parsedCategory?.pictureCollection)
        
        let collectionObject = self.categoryJSONDict?["pictures"] as? Dictionary<String, Any>
        let picturesArray = collectionObject?["sizes"] as? [Dictionary<String, Any>]
        
        XCTAssertEqual(self.parsedCategory?.pictureCollection?.uri, collectionObject?["uri"] as? String)
        
        var i = 0
        for picture in self.parsedCategory?.pictureCollection?.pictures as! [VIMPicture]
        {
            XCTAssertNotNil(picture.link)
            XCTAssertNotNil(picture.width)
            XCTAssertNotNil(picture.height)
            
            XCTAssertEqual(picture.link, picturesArray?[i]["link"] as? String)
            XCTAssertEqual(picture.width, picturesArray?[i]["width"] as? NSNumber)
            XCTAssertEqual(picture.height, picturesArray?[i]["height"] as? NSNumber)
            
            i = i + 1
        }
    }
    
    func test_VIMCategory_ConnectionParsing()
    {
        XCTAssertNotNil(self.parsedCategory?.connection(withName: VIMConnectionNameGroups))
        XCTAssertNotNil(self.parsedCategory?.connection(withName: VIMConnectionNameChannels))
        XCTAssertNotNil(self.parsedCategory?.connection(withName: VIMConnectionNameVideos))
        XCTAssertNotNil(self.parsedCategory?.connection(withName: VIMConnectionNameUsers))
    }
    
    func test_Performance_ParsingCategoryObject()
    {
        guard let categoryJSONDict = ResponseUtilities.loadResponse(from: "categories-animation-response.json") else
        {
            XCTFail("unable to load response data from file")
            return
        }
        
        self.measure {
            let parsedCategory = try! VIMObjectMapper.mapObject(responseDictionary: categoryJSONDict) as VIMCategory
            XCTAssertNotNil(parsedCategory)
        }
    }
    
}
